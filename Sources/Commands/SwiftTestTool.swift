/*
This source file is part of the Swift.org open source project

Copyright 2015 - 2016 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import class Foundation.ProcessInfo

import Basic
import Build
import SPMUtility
import PackageGraph
import Workspace

import func SPMLibc.exit


/// Diagnostics info for deprecated `--specifier` option.
struct SpecifierDeprecatedDiagnostic: DiagnosticData {
    static let id = DiagnosticID(
        type: SpecifierDeprecatedDiagnostic.self,
        name: "org.swift.diags.specifier-deprecated",
        defaultBehavior: .warning,
        description: {
            $0 <<< "'--specifier' option is deprecated; use '--filter' instead"
        }
    )
}

struct LinuxTestDiscoveryDiagnostic: DiagnosticData {
    static let id = DiagnosticID(
        type: LinuxTestDiscoveryDiagnostic.self,
        name: "org.swift.diags.linux-test-discovery",
        defaultBehavior: .warning,
        description: {
            $0 <<< "can't discover tests on Linux; please use this option on macOS instead"
        }
    )
}

/// Diagnostic data for zero --filter matches.
struct NoMatchingTestsWarning: DiagnosticData {
    static let id = DiagnosticID(
        type: NoMatchingTestsWarning.self,
        name: "org.swift.diags.no-matching-tests",
        defaultBehavior: .note,
        description: {
            $0 <<< "'--filter' predicate did not match any test case"
        }
    )
}

/// Diagnostic error when a command is run without its dependent command.
struct DependentArgumentDiagnostic: DiagnosticData {
    static let id = DiagnosticID(
        type: DependentArgumentDiagnostic.self,
        name: "org.swift.diags.dependent-argument",
        defaultBehavior: .error,
        description: {
            $0 <<< { "\($0.dependentArgument)" } <<< "must be used with" <<< { "\($0.requiredArgument)" }
        }
    )

    let requiredArgument: String

    let dependentArgument: String
}

/// Diagnostic error for unsatisfied --num-workers parameter
struct InvalidNumWorkersValueDiagnostic: DiagnosticData {
    static let id = DiagnosticID(
        type: InvalidNumWorkersValueDiagnostic.self,
        name: "org.swift.diags.invalid-numWorkers-value",
        defaultBehavior: .error,
        description: {
            $0 <<< "'--num-workers' must be greater than zero"
        }
    )
}

private enum TestError: Swift.Error {
    case invalidListTestJSONData
    case testsExecutableNotFound
}

extension TestError: CustomStringConvertible {
    var description: String {
        switch self {
        case .testsExecutableNotFound:
            return "no tests found; create a target in the 'Tests' directory"
        case .invalidListTestJSONData:
            return "invalid list test JSON structure"
        }
    }
}

public class TestToolOptions: ToolOptions {
    /// Returns the mode in with the tool command should run.
    var mode: TestMode {
        // If we got version option, just print the version and exit.
        if shouldPrintVersion {
            return .version
        }

        if shouldRunInParallel {
            return .runParallel
        }

        if shouldListTests {
            return .listTests
        }

        if shouldGenerateLinuxMain {
            return .generateLinuxMain
        }

        return .runSerial
    }

    /// If the test target should be built before testing.
    var shouldBuildTests = true

    /// If tests should run in parallel mode.
    var shouldRunInParallel = false

    /// Number of tests to execute in parallel
    var numberOfWorkers: Int?

    /// List the tests and exit.
    var shouldListTests = false

    /// Generate LinuxMain entries and exit.
    var shouldGenerateLinuxMain = false

    var testCaseSpecifier: TestCaseSpecifier {
        testCaseSpecifierOverride() ?? _testCaseSpecifier
    }

    var _testCaseSpecifier: TestCaseSpecifier = .none

    /// Path where the xUnit xml file should be generated.
    var xUnitOutput: AbsolutePath?

    /// Returns the test case specifier if overridden in the env.
    private func testCaseSpecifierOverride() -> TestCaseSpecifier? {
        guard let override = ProcessEnv.vars["_SWIFTPM_SKIP_TESTS_LIST"] else {
            return nil
        }

        do {
            let skipTests: [String.SubSequence]
            // Read from the file if it exists.
            if let path = try? AbsolutePath(validating: override), localFileSystem.exists(path) {
                let contents = try localFileSystem.readFileContents(path).cString
                skipTests = contents.split(separator: "\n", omittingEmptySubsequences: true)
            } else {
                // Otherwise, read the env variable.
                skipTests = override.split(separator: ":", omittingEmptySubsequences: true)
            }

            return .skip(skipTests.map(String.init))
        } catch {
            // FIXME: We should surface errors from here.
        }
        return nil
    }
}

/// Tests filtering specifier
///
/// This is used to filter tests to run
///   .none     => No filtering
///   .specific => Specify test with fully quantified name
///   .regex    => RegEx pattern
public enum TestCaseSpecifier {
    case none
    case specific(String)
    case regex(String)
    case skip([String])
}

public enum TestMode {
    case version
    case listTests
    case generateLinuxMain
    case runSerial
    case runParallel
}

/// swift-test tool namespace
public class SwiftTestTool: SwiftTool<TestToolOptions> {

   public convenience init(args: [String]) {
       self.init(
            toolName: "test",
            usage: "[options]",
            overview: "Build and run tests",
            args: args,
            seeAlso: type(of: self).otherToolNames()
        )
    }

    override func runImpl() throws {

        // Validate commands arguments
        try validateArguments()

        switch options.mode {
        case .version:
            print(Versioning.currentVersion.completeDisplayString)

        case .listTests:
            let graph = try loadPackageGraph()
            let buildPlan = try BuildPlan(buildParameters: self.buildParameters(), graph: graph, diagnostics: diagnostics)
            let testPath = try buildTestsIfNeeded(buildPlan)
            let testSuites = try getTestSuites(path: testPath)
            let tests = testSuites.filteredTests(specifier: options.testCaseSpecifier)

            // Print the tests.
            for test in tests {
                print(test.specifier)
            }

        case .generateLinuxMain:
          #if os(Linux)
            diagnostics.emit(data: LinuxTestDiscoveryDiagnostic())
          #endif
            let graph = try loadPackageGraph()
            let buildPlan = try BuildPlan(buildParameters: self.buildParameters(), graph: graph, diagnostics: diagnostics)
            let testPath = try buildTestsIfNeeded(buildPlan)
            let testSuites = try getTestSuites(path: testPath)
            let generator = LinuxMainGenerator(graph: graph, testSuites: testSuites)
            try generator.generate()

        case .runSerial:
            let toolchain = try getToolchain()
            let graph = try loadPackageGraph()
            let buildPlan = try BuildPlan(buildParameters: self.buildParameters(), graph: graph, diagnostics: diagnostics)
            let testPath = try buildTestsIfNeeded(buildPlan)
            var ranSuccessfully = true
            let buildParameters = try self.buildParameters()

            // Clean out the code coverage directory that may contain stale
            // profraw files from a previous run of the code coverage tool.
            if options.shouldEnableCodeCoverage {
                try localFileSystem.removeFileTree(buildParameters.codeCovPath)
            }

            switch options.testCaseSpecifier {
            case .none:
                let runner = TestRunner(
                    path: testPath,
                    xctestArg: nil,
                    processSet: processSet,
                    toolchain: toolchain,
                    diagnostics: diagnostics,
                    options: self.options,
                    buildParameters: buildParameters
                )
                ranSuccessfully = runner.test()

            case .regex, .specific, .skip:
                // If old specifier `-s` option was used, emit deprecation notice.
                if case .specific = options.testCaseSpecifier {
                    diagnostics.emit(data: SpecifierDeprecatedDiagnostic())
                }

                // Find the tests we need to run.
                let testSuites = try getTestSuites(path: testPath)
                let tests = testSuites.filteredTests(specifier: options.testCaseSpecifier)

                // If there were no matches, emit a warning.
                if tests.isEmpty {
                    diagnostics.emit(data: NoMatchingTestsWarning())
                }

                // Finally, run the tests.
                for test in tests {
                    let runner = TestRunner(
                        path: testPath,
                        xctestArg: test.specifier,
                        processSet: processSet,
                        toolchain: toolchain,
                        diagnostics: diagnostics,
                        options: self.options,
                        buildParameters: try self.buildParameters()
                    )
                    ranSuccessfully = runner.test() && ranSuccessfully
                }
            }

            if !ranSuccessfully {
                executionStatus = .failure
            }

            if options.shouldEnableCodeCoverage {
                try processCodeCoverage(buildPlan)
            }

        case .runParallel:
            let toolchain = try getToolchain()
            let graph = try loadPackageGraph()
            let buildPlan = try BuildPlan(buildParameters: self.buildParameters(), graph: graph, diagnostics: diagnostics)
            let testPath = try buildTestsIfNeeded(buildPlan)
            let testSuites = try getTestSuites(path: testPath)
            let tests = testSuites.filteredTests(specifier: options.testCaseSpecifier)
            let buildParameters = try self.buildParameters()

            // If there were no matches, emit a warning and exit.
            if tests.isEmpty {
                diagnostics.emit(data: NoMatchingTestsWarning())
                return
            }

            // Clean out the code coverage directory that may contain stale
            // profraw files from a previous run of the code coverage tool.
            if options.shouldEnableCodeCoverage {
                try localFileSystem.removeFileTree(buildParameters.codeCovPath)
            }

            // Run the tests using the parallel runner.
            let runner = ParallelTestRunner(
                testPath: testPath,
                processSet: processSet,
                toolchain: toolchain,
                xUnitOutput: options.xUnitOutput,
                numJobs: options.numberOfWorkers ?? ProcessInfo.processInfo.activeProcessorCount,
                diagnostics: diagnostics,
                options: self.options,
                buildParameters: buildParameters
            )
            try runner.run(tests)

            if !runner.ranSuccessfully {
                executionStatus = .failure
            }

            if options.shouldEnableCodeCoverage {
                try processCodeCoverage(buildPlan)
            }
        }
    }

    /// Processes the code coverage data and emits a json.
    private func processCodeCoverage(_ buildPlan: BuildPlan) throws {
        // Merge all the profraw files to produce a single profdata file.
        try mergeCodeCovRawDataFiles()

        // Get the test product.
        guard let testProduct = buildPlan.buildProducts.first(where: { $0.product.type == .test }) else {
            throw TestError.testsExecutableNotFound
        }

        // Export the codecov data as JSON.
        try exportCodeCovAsJSON(filename: buildPlan.graph.rootPackages[0].name, testBinary: testProduct.binary)
    }

    /// Merges all profraw profiles in codecoverage directory into default.profdata file.
    private func mergeCodeCovRawDataFiles() throws {
        // Get the llvm-prof tool.
        let llvmProf = try getToolchain().getLLVMProf()

        // Get the profraw files.
        let buildParameters = try self.buildParameters()
        let codeCovFiles = try localFileSystem.getDirectoryContents(buildParameters.codeCovPath)

        // Construct arguments for invoking the llvm-prof tool.
        var args = [llvmProf.pathString, "merge", "-sparse"]
        for file in codeCovFiles {
            let filePath = buildParameters.codeCovPath.appending(component: file)
            if filePath.extension == "profraw" {
                args.append(filePath.pathString)
            }
        }
        args += ["-o", buildParameters.codeCovDataFile.pathString]

        try Process.checkNonZeroExit(arguments: args)
    }

    /// Exports profdata as a JSON file.
    private func exportCodeCovAsJSON(filename: String, testBinary: AbsolutePath) throws {
        // Export using the llvm-cov tool.
        let llvmCov = try getToolchain().getLLVMCov()
        let buildParameters = try self.buildParameters()
        let args = [
            llvmCov.pathString,
            "export",
            "-instr-profile=\(buildParameters.codeCovDataFile)",
            testBinary.pathString
        ]
        let result = try Process.popen(arguments: args)

        // Write to a file.
        let jsonPath = buildParameters.codeCovPath.appending(component:  filename + ".json")
        try localFileSystem.writeFileContents(jsonPath, bytes: ByteString(result.output.dematerialize()))
    }

    /// Builds the "test" target if enabled in options.
    ///
    /// - Returns: The path to the test binary.
    private func buildTestsIfNeeded(_ buildPlan: BuildPlan) throws -> AbsolutePath {
        if options.shouldBuildTests {
            try build(plan: buildPlan, subset: .allIncludingTests)
        }

        guard let testProduct = buildPlan.buildProducts.first(where: { $0.product.type == .test }) else {
            throw TestError.testsExecutableNotFound
        }

        // Go up the folder hierarchy until we find the .xctest bundle.
        return sequence(first: testProduct.binary, next: {
            $0.isRoot ? nil : $0.parentDirectory
        }).first(where: {
            $0.basename.hasSuffix(".xctest")
        })!
    }

    override class func defineArguments(parser: ArgumentParser, binder: ArgumentBinder<TestToolOptions>) {

        binder.bind(
            option: parser.add(option: "--skip-build", kind: Bool.self,
                usage: "Skip building the test target"),
            to: { $0.shouldBuildTests = !$1 })

        binder.bind(
            option: parser.add(option: "--list-tests", shortName: "-l", kind: Bool.self,
                usage: "Lists test methods in specifier format"),
            to: { $0.shouldListTests = $1 })

        binder.bind(
            option: parser.add(option: "--generate-linuxmain", kind: Bool.self,
                usage: "Generate LinuxMain.swift entries for the package"),
            to: { $0.shouldGenerateLinuxMain = $1 })

        binder.bind(
            option: parser.add(option: "--parallel", kind: Bool.self,
                usage: "Run the tests in parallel."),
            to: { $0.shouldRunInParallel = $1 })

        binder.bind(
            option: parser.add(option: "--num-workers", kind: Int.self,
                               usage: "Number of tests to execute in parallel."),
            to: { $0.numberOfWorkers = $1 })

        binder.bind(
            option: parser.add(option: "--specifier", shortName: "-s", kind: String.self),
            to: { $0._testCaseSpecifier = .specific($1) })

        binder.bind(
            option: parser.add(option: "--xunit-output", kind: PathArgument.self),
            to: { $0.xUnitOutput = $1.path })

        binder.bind(
            option: parser.add(option: "--filter", kind: String.self,
                usage: "Run test cases matching regular expression, Format: <test-target>.<test-case> or " +
                    "<test-target>.<test-case>/<test>"),
            to: { $0._testCaseSpecifier = .regex($1) })

        binder.bind(
            option: parser.add(option: "--enable-code-coverage", kind: Bool.self,
                usage: "Test with code coverage enabled"),
            to: { $0.shouldEnableCodeCoverage = $1 })
    }

    /// Locates XCTestHelper tool inside the libexec directory and bin directory.
    /// Note: It is a fatalError if we are not able to locate the tool.
    ///
    /// - Returns: Path to XCTestHelper tool.
    private static func xctestHelperPath() -> AbsolutePath {
        let xctestHelperBin = "swiftpm-xctest-helper"
        let binDirectory = AbsolutePath(CommandLine.arguments.first!,
            relativeTo: localFileSystem.currentWorkingDirectory!).parentDirectory
        // XCTestHelper tool is installed in libexec.
        let maybePath = binDirectory.parentDirectory.appending(components: "libexec", "swift", "pm", xctestHelperBin)
        if localFileSystem.isFile(maybePath) {
            return maybePath
        }
        // This will be true during swiftpm development.
        // FIXME: Factor all of the development-time resource location stuff into a common place.
        let path = binDirectory.appending(component: xctestHelperBin)
        if localFileSystem.isFile(path) {
            return path
        }
        fatalError("XCTestHelper binary not found.")
    }

    /// Runs the corresponding tool to get tests JSON and create TestSuite array.
    /// On macOS, we use the swiftpm-xctest-helper tool bundled with swiftpm.
    /// On Linux, XCTest can dump the json using `--dump-tests-json` mode.
    ///
    /// - Parameters:
    ///     - path: Path to the XCTest bundle(macOS) or executable(Linux).
    ///
    /// - Throws: TestError, SystemError, SPMUtility.Error
    ///
    /// - Returns: Array of TestSuite
    fileprivate func getTestSuites(path: AbsolutePath) throws -> [TestSuite] {
        // Run the correct tool.
      #if os(macOS)
        let tempFile = try TemporaryFile()
        let args = [SwiftTestTool.xctestHelperPath().pathString, path.pathString, tempFile.path.pathString]
        var env = try constructTestEnvironment(toolchain: try getToolchain(), options: self.options, buildParameters: self.buildParameters())
        // Add the sdk platform path if we have it. If this is not present, we
        // might always end up failing.
        if let sdkPlatformFrameworksPath = Destination.sdkPlatformFrameworkPath() {
            env["DYLD_FRAMEWORK_PATH"] = sdkPlatformFrameworksPath.pathString
        }
        try Process.checkNonZeroExit(arguments: args, environment: env)
        // Read the temporary file's content.
        let data = try localFileSystem.readFileContents(tempFile.path).validDescription ?? ""
      #else
        let args = [path.description, "--dump-tests-json"]
        let data = try Process.checkNonZeroExit(arguments: args)
      #endif
        // Parse json and return TestSuites.
        return try TestSuite.parse(jsonString: data)
    }

    /// Private function that validates the commands arguments
    ///
    /// - Throws: if a command argument is invalid
    private func validateArguments() throws {

        // Validation for --num-workers.
        if let workers = options.numberOfWorkers {

            // The --num-worker option should be called with --parallel.
            guard options.mode == .runParallel else {
                diagnostics.emit(
                    data: DependentArgumentDiagnostic(requiredArgument: "--parallel", dependentArgument: "--num-workers"))
                throw Diagnostics.fatalError
            }

            guard workers > 0 else {
                diagnostics.emit(data: InvalidNumWorkersValueDiagnostic())
                throw Diagnostics.fatalError
            }
        }
    }
}

/// A structure representing an individual unit test.
struct UnitTest {
    /// The name of the unit test.
    let name: String

    /// The name of the test case.
    let testCase: String

    /// The specifier argument which can be passed to XCTest.
    var specifier: String {
        return testCase + "/" + name
    }
}

/// A class to run tests on a XCTest binary.
///
/// Note: Executes the XCTest with inherited environment as it is convenient to pass senstive
/// information like username, password etc to test cases via environment variables.
final class TestRunner {
    /// Path to valid XCTest binary.
    private let path: AbsolutePath

    /// Arguments to pass to XCTest if any.
    private let xctestArg: String?

    private let processSet: ProcessSet

    // The toolchain to use.
    private let toolchain: UserToolchain

    /// Diagnostics Engine to emit diagnostics.
    let diagnostics: DiagnosticsEngine

    private let options: ToolOptions

    private let buildParameters: BuildParameters

    /// Creates an instance of TestRunner.
    ///
    /// - Parameters:
    ///     - path: Path to valid XCTest binary.
    ///     - xctestArg: Arguments to pass to XCTest.
    init(path: AbsolutePath,
         xctestArg: String? = nil,
         processSet: ProcessSet,
         toolchain: UserToolchain,
         diagnostics: DiagnosticsEngine,
         options: ToolOptions,
         buildParameters: BuildParameters
    ) {
        self.path = path
        self.xctestArg = xctestArg
        self.processSet = processSet
        self.toolchain = toolchain
        self.diagnostics = diagnostics
        self.options = options
        self.buildParameters = buildParameters
    }

    /// Constructs arguments to execute XCTest.
    private func args() throws -> [String] {
        var args: [String] = []
      #if os(macOS)
        guard let xctest = toolchain.xctest else {
            throw TestError.testsExecutableNotFound
        }
        args = [xctest.pathString]
        if let xctestArg = xctestArg {
            args += ["-XCTest", xctestArg]
        }
        args += [path.pathString]
      #else
        args += [path.description]
        if let xctestArg = xctestArg {
            args += [xctestArg]
        }
      #endif
        return args
    }

    /// Executes the tests without printing anything on standard streams.
    ///
    /// - Returns: A tuple with first bool member indicating if test execution returned code 0
    ///            and second argument containing the output of the execution.
    func test() -> (Bool, String) {
        var output = ""
        var success = false
        do {
            // FIXME: The environment will be constructed for every test when using the
            // parallel test runner. We should do some kind of caching.
            let env = try constructTestEnvironment(toolchain: toolchain, options: self.options, buildParameters: self.buildParameters)
            let process = Process(arguments: try args(), environment: env, outputRedirection: .collect, verbose: false)
            try process.launch()
            let result = try process.waitUntilExit()
            output = try (result.utf8Output() + result.utf8stderrOutput()).spm_chuzzle() ?? ""
            switch result.exitStatus {
            case .terminated(code: 0):
                success = true
            case .signalled(let signal):
                output += "\n" + exitSignalText(code: signal)
            default: break
            }
        } catch {
            diagnostics.emit(error)
        }
        return (success, output)
    }

    /// Executes and returns execution status. Prints test output on standard streams.
    func test() -> Bool {
        do {
            let env = try constructTestEnvironment(toolchain: toolchain, options: self.options, buildParameters: self.buildParameters)
            let process = Process(arguments: try args(), environment: env, outputRedirection: .none)
            try processSet.add(process)
            try process.launch()
            let result = try process.waitUntilExit()
            switch result.exitStatus {
            case .terminated(code: 0):
                return true
            case .signalled(let signal):
                print(exitSignalText(code: signal))
            default: break
            }
        } catch {
            diagnostics.emit(error)
        }
        return false
    }

    private func exitSignalText(code: Int32) -> String {
        return "Exited with signal code \(code)"
    }
}

/// A class to run tests in parallel.
final class ParallelTestRunner {
    /// An enum representing result of a unit test execution.
    struct TestResult {
        var unitTest: UnitTest
        var output: String
        var success: Bool
    }

    /// Path to XCTest binary.
    private let testPath: AbsolutePath

    /// The queue containing list of tests to run (producer).
    private let pendingTests = SynchronizedQueue<UnitTest?>()

    /// The queue containing tests which are finished running.
    private let finishedTests = SynchronizedQueue<TestResult?>()

    /// Instance of a terminal progress animation.
    private let progressAnimation: ProgressAnimationProtocol

    /// Number of tests that will be executed.
    private var numTests = 0

    /// Number of the current tests that has been executed.
    private var numCurrentTest = 0

    /// True if all tests executed successfully.
    private(set) var ranSuccessfully = true

    let processSet: ProcessSet

    let toolchain: UserToolchain
    let xUnitOutput: AbsolutePath?

    let options: ToolOptions
    let buildParameters: BuildParameters

    /// Number of tests to execute in parallel.
    let numJobs: Int

    /// Diagnostics Engine to emit diagnostics.
    let diagnostics: DiagnosticsEngine

    init(
        testPath: AbsolutePath,
        processSet: ProcessSet,
        toolchain: UserToolchain,
        xUnitOutput: AbsolutePath? = nil,
        numJobs: Int,
        diagnostics: DiagnosticsEngine,
        options: ToolOptions,
        buildParameters: BuildParameters
    ) {
        self.testPath = testPath
        self.processSet = processSet
        self.toolchain = toolchain
        self.xUnitOutput = xUnitOutput
        self.numJobs = numJobs
        self.diagnostics = diagnostics

        if Process.env["SWIFTPM_TEST_RUNNER_PROGRESS_BAR"] == "lit" {
            progressAnimation = PercentProgressAnimation(stream: stdoutStream, header: "Testing:")
        } else {
            progressAnimation = NinjaProgressAnimation(stream: stdoutStream)
        }

        self.options = options
        self.buildParameters = buildParameters

        assert(numJobs > 0, "num jobs should be > 0")
    }

    /// Whether to display output from successful tests.
    private var shouldOutputSuccess: Bool {
        // FIXME: It is weird to read Process's verbosity to determine this, we
        // should improve our verbosity infrastructure.
        return Process.verbose
    }

    /// Updates the progress bar status.
    private func updateProgress(for test: UnitTest) {
        numCurrentTest += 1
        progressAnimation.update(step: numCurrentTest, total: numTests, text: "Testing \(test.specifier)")
    }

    private func enqueueTests(_ tests: [UnitTest]) throws {
        // FIXME: Add a count property in SynchronizedQueue.
        var numTests = 0
        // Enqueue all the tests.
        for test in tests {
            numTests += 1
            pendingTests.enqueue(test)
        }
        self.numTests = numTests
        self.numCurrentTest = 0
        // Enqueue the sentinels, we stop a thread when it encounters a sentinel in the queue.
        for _ in 0..<numJobs {
            pendingTests.enqueue(nil)
        }
    }

    /// Executes the tests spawning parallel workers. Blocks calling thread until all workers are finished.
    func run(_ tests: [UnitTest]) throws {
        assert(!tests.isEmpty, "There should be at least one test to execute.")
        // Enqueue all the tests.
        try enqueueTests(tests)

        // Create the worker threads.
        let workers: [Thread] = (0..<numJobs).map({ _ in
            let thread = Thread {
                // Dequeue a specifier and run it till we encounter nil.
                while let test = self.pendingTests.dequeue() {
                    let testRunner = TestRunner(
                        path: self.testPath,
                        xctestArg: test.specifier,
                        processSet: self.processSet,
                        toolchain: self.toolchain,
                        diagnostics: self.diagnostics,
                        options: self.options,
                        buildParameters: self.buildParameters
                    )
                    let (success, output) = testRunner.test()
                    if !success {
                        self.ranSuccessfully = false
                    }
                    self.finishedTests.enqueue(TestResult(unitTest: test, output: output, success: success))
                }
            }
            thread.start()
            return thread
        })

        // List of processed tests.
        var processedTests: [TestResult] = []
        let processedTestsLock = Basic.Lock()

        // Report (consume) the tests which have finished running.
        while let result = finishedTests.dequeue() {
            updateProgress(for: result.unitTest)

            // Store the result.
            processedTestsLock.withLock {
                processedTests.append(result)
            }

            // We can't enqueue a sentinel into finished tests queue because we won't know
            // which test is last one so exit this when all the tests have finished running.
            if numCurrentTest == numTests {
                break
            }
        }

        // Wait till all threads finish execution.
        workers.forEach { $0.join() }

        // Report the completion.
        progressAnimation.complete(success: processedTests.contains(where: { !$0.success }))

        // Print test results.
        for test in processedTests {
            if !test.success || shouldOutputSuccess {
                print(test)
            }
        }

        // Generate xUnit file if requested.
        if let xUnitOutput = xUnitOutput {
            try XUnitGenerator(processedTests).generate(at: xUnitOutput)
        }
    }

    // Print a test result.
    private func print(_ test: TestResult) {
        stdoutStream <<< "\n"
        stdoutStream <<< test.output
        if !test.output.isEmpty {
            stdoutStream <<< "\n"
        }
        stdoutStream.flush()
    }
}

/// A struct to hold the XCTestSuite data.
struct TestSuite {

    /// A struct to hold a XCTestCase data.
    struct TestCase {
        /// Name of the test case.
        let name: String

        /// Array of test methods in this test case.
        let tests: [String]
    }

    /// The name of the test suite.
    let name: String

    /// Array of test cases in this test suite.
    let tests: [TestCase]

    /// Parses a JSON String to array of TestSuite.
    ///
    /// - Parameters:
    ///     - jsonString: JSON string to be parsed.
    ///
    /// - Throws: JSONDecodingError, TestError
    ///
    /// - Returns: Array of TestSuite.
    static func parse(jsonString: String) throws -> [TestSuite] {
        let json = try JSON(string: jsonString)
        return try TestSuite.parse(json: json)
    }

    /// Parses the JSON object into array of TestSuite.
    ///
    /// - Parameters:
    ///     - json: An object of JSON.
    ///
    /// - Throws: TestError
    ///
    /// - Returns: Array of TestSuite.
    static func parse(json: JSON) throws -> [TestSuite] {
        guard case let .dictionary(contents) = json,
              case let .array(testSuites)? = contents["tests"] else {
            throw TestError.invalidListTestJSONData
        }

        return try testSuites.map({ testSuite in
            guard case let .dictionary(testSuiteData) = testSuite,
                  case let .string(name)? = testSuiteData["name"],
                  case let .array(allTestsData)? = testSuiteData["tests"] else {
                throw TestError.invalidListTestJSONData
            }

            let testCases: [TestSuite.TestCase] = try allTestsData.map({ testCase in
                guard case let .dictionary(testCaseData) = testCase,
                      case let .string(name)? = testCaseData["name"],
                      case let .array(tests)? = testCaseData["tests"] else {
                    throw TestError.invalidListTestJSONData
                }
                let testMethods: [String] = try tests.map({ test in
                    guard case let .dictionary(testData) = test,
                          case let .string(testMethod)? = testData["name"] else {
                        throw TestError.invalidListTestJSONData
                    }
                    return testMethod
                })
                return TestSuite.TestCase(name: name, tests: testMethods)
            })

            return TestSuite(name: name, tests: testCases)
        })
    }
}


fileprivate extension Sequence where Iterator.Element == TestSuite {
    /// Returns all the unit tests of the test suites.
    var allTests: [UnitTest] {
        return flatMap { $0.tests }.flatMap({ testCase in
            testCase.tests.map{ UnitTest(name: $0, testCase: testCase.name) }
        })
    }

    /// Return tests matching the provided specifier
    func filteredTests(specifier: TestCaseSpecifier) -> [UnitTest] {
        switch specifier {
        case .none:
            return allTests
        case .regex(let pattern):
            return allTests.filter({ test in
                test.specifier.range(of: pattern,
                                     options: .regularExpression) != nil
            })
        case .specific(let name):
            return allTests.filter{ $0.specifier == name }
        case .skip(let skippedTests):
            var result = allTests
            for skippedTest in skippedTests {
                result = result.filter{
                    $0.specifier.range(of: skippedTest, options: .regularExpression) == nil
                }
            }
            return result
        }
    }
}

extension SwiftTestTool: ToolName {
    static var toolName: String {
        return "swift test"
    }
}

/// Creates the environment needed to test related tools.
fileprivate func constructTestEnvironment(
    toolchain: UserToolchain,
    options: ToolOptions,
    buildParameters: BuildParameters
) throws -> [String: String] {
    var env = Process.env

    // Add the code coverage related variables.
    if options.shouldEnableCodeCoverage {
        // Defines the path at which the profraw files will be written on test execution.
        //
        // `%m` will create a pool of profraw files and append the data from
        // each execution in one of the files. This doesn't matter for serial
        // execution but is required when the tests are running in parallel as
        // SwiftPM repeatedly invokes the test binary with the test case name as
        // the filter.
        let codecovProfile = buildParameters.buildPath.appending(components: "codecov", "default%m.profraw")
        env["LLVM_PROFILE_FILE"] = codecovProfile.pathString
    }

  #if !os(macOS)
    return env
  #else
    // Fast path when no sanitizers are enabled.
    if options.sanitizers.isEmpty {
        return env
    }

    // Get the runtime libraries.
    var runtimes = try options.sanitizers.sanitizers.map({ sanitizer in
        return try toolchain.runtimeLibrary(for: sanitizer).pathString
    })

    // Append any existing value to the front.
    if let existingValue = env["DYLD_INSERT_LIBRARIES"], !existingValue.isEmpty {
        runtimes.insert(existingValue, at: 0)
    }

    env["DYLD_INSERT_LIBRARIES"] = runtimes.joined(separator: ":")
    return env
  #endif
}

/// xUnit XML file generator for a swift-test run.
final class XUnitGenerator {
    typealias TestResult = ParallelTestRunner.TestResult

    /// The test results.
    let results: [TestResult]

    init(_ results: [TestResult]) {
        self.results = results
    }

    /// Generate the file at the given path.
    func generate(at path: AbsolutePath) throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            <?xml version="1.0" encoding="UTF-8"?>

            """
        stream <<< "<testsuites>\n"

        // Get the failure count.
        let failures = results.filter({ !$0.success }).count

        // FIXME: This should contain the right elapsed time.
        //
        // We need better output reporting from XCTest.
        stream <<< """
            <testsuite name="TestResults" errors="0" tests="\(results.count)" failures="\(failures)" time="0.0">

            """

        // Generate a testcase entry for each result.
        //
        // FIXME: This is very minimal right now. We should allow including test output etc.
        for result in results {
            let test = result.unitTest
            stream <<< """
                <testcase classname="\(test.testCase)" name="\(test.name)" time="0.0">

                """

            if !result.success {
                stream <<< "<failure message=\"failed\"></failure>\n"
            }

            stream <<< "</testcase>\n"
        }

        stream <<< "</testsuite>\n"
        stream <<< "</testsuites>\n"

        try localFileSystem.writeFileContents(path, bytes: stream.bytes)
    }
}
