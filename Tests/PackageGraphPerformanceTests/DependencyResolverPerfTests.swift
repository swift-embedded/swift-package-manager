/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import PackageGraph

import struct Utility.Version

import TestSupport

#if ENABLE_PERF_TESTS

private let v1: Version = "1.0.0"
private let v1Range: VersionSetSpecifier = .range("1.0.0" ..< "2.0.0")

class DependencyResolverPerfTests: XCTestCase {

    func testTrivalResolution_X1000() {
        let N = 1000
        // Try resolving a trivial graph:
        //        ↗ C
        // A -> B
        //        ↘ D
        let provider = MockPackagesProvider(containers: [
            MockPackageContainer(name: "A", dependenciesByVersion: [
                v1: [(container: "B", versionRequirement: v1Range)]]),
            MockPackageContainer(name: "B", dependenciesByVersion: [
                v1: [
                    (container: "C", versionRequirement: v1Range),
                    (container: "D", versionRequirement: v1Range),
                ]
            ]),
            MockPackageContainer(name: "C", dependenciesByVersion: [
                v1: []]),
            MockPackageContainer(name: "D", dependenciesByVersion: [
                v1: []])
        ])
        let resolver = MockDependencyResolver(provider, MockResolverDelegate())
        measure {
            for _ in 0..<N {
                let result = try! resolver.resolve(constraints: [MockPackageConstraint(container: "A", versionRequirement: v1Range)])
                XCTAssertEqual(result, ["A": v1, "B": v1, "C": v1, "D": v1])
            }
        }
    }

    func testResolutionWith100Depth1Breadth() {
        let N = 1
        let depth = 100
        let breadth = 1

        let graph = createDummyGraph(depth: depth, breadth: breadth)
        let provider = MockPackagesProvider(containers: graph.containers)

        measure {
            for _ in 0..<N {
                let resolver = MockDependencyResolver(provider, MockResolverDelegate())
                let result = try! resolver.resolve(constraints: [graph.rootConstraint])
                XCTAssertEqual(result.count, depth * breadth)
            }
        }
    }

    func testResolutionWith100Depth2Breadth() {
        let N = 1
        let depth = 100
        let breadth = 2

        let graph = createDummyGraph(depth: depth, breadth: breadth)
        let provider = MockPackagesProvider(containers: graph.containers)

        measure {
            for _ in 0..<N {
                let resolver = MockDependencyResolver(provider, MockResolverDelegate())
                let result = try! resolver.resolve(constraints: [graph.rootConstraint])
                XCTAssertEqual(result.count, depth * breadth)
            }
        }
    }

    func testResolutionWith1Depth100Breadth() {
        let N = 1
        let depth = 1
        let breadth = 100

        let graph = createDummyGraph(depth: depth, breadth: breadth)
        let provider = MockPackagesProvider(containers: graph.containers)

        measure {
            for _ in 0..<N {
                let resolver = MockDependencyResolver(provider, MockResolverDelegate())
                let result = try! resolver.resolve(constraints: [graph.rootConstraint])
                XCTAssertEqual(result.count, depth * breadth)
            }
        }
    }

    func testResolutionWith10Depth20Breadth() {
        let N = 1
        let depth = 10
        let breadth = 20

        let graph = createDummyGraph(depth: depth, breadth: breadth)
        let provider = MockPackagesProvider(containers: graph.containers)

        measure {
            for _ in 0..<N {
                let resolver = MockDependencyResolver(provider, MockResolverDelegate())
                let result = try! resolver.resolve(constraints: [graph.rootConstraint])
                XCTAssertEqual(result.count, depth * breadth)
            }
        }
    }

    func testKitura() throws {
        try runPackageTest(name: "kitura.json")
    }

    func testZewoHTTPServer() throws {
        try runPackageTest(name: "ZewoHTTPServer.json")
    }

    func testPerfectHTTPServer() throws {
        try runPackageTest(name: "PerfectHTTPServer.json")
    }

    func testSourceKitten_X100() throws {
        try runPackageTest(name: "SourceKitten.json", N: 100)
    }
    
    func runPackageTest(name: String, N: Int = 0) throws {
        let N = 100
        let graph = try mockGraph(for: name)
        let provider = MockPackagesProvider(containers: graph.containers)
        
        measure {
            for _ in 0 ..< N {
                let resolver = MockDependencyResolver(provider, MockResolverDelegate())
                let result = try! resolver.resolve(constraints: graph.constraints)
                graph.checkResult(result)
            }
        }
    }

    func mockGraph(for name: String) throws -> MockGraph {
        let input = AbsolutePath(#file).parentDirectory.appending(component: "Inputs").appending(component: name)
        let jsonString = try localFileSystem.readFileContents(input)
        let json = try JSON(bytes: jsonString)
        return MockGraph(json)
    }
}

/// Create dummpy graph with depth X breadth nodes.
///
/// This method creates a graph with `depth` number of main nodes. Each main node is dependent on the next main node and
/// `breadth` number of child nodes. This is how a graph looks like:
///     +---+    +---+    +---+    +---+
///     |   +--->+   +--->+   +--->+   |  Depth = 4
///     +-+-+    +-+-+    +-+-+    +-+-+
///       |        |        |        |
///       v        v        v        v
///     +-+-+    +-+-+    +-+-+    +-+-+
///     |   |    |   |    |   |    |   |
///     +-+-+    +-+-+    +-+-+    +-+-+
///       |        |        |        |
///       v        v        v        v
///     +-+-+    +-+-+    +-+-+    +-+-+
///     |   |    |   |    |   |    |   |
///     +---+    +---+    +---+    +---+
///
///                 Breadth = 3
///
/// - Parameters:
///   - depth: The number of main nodes.
///   - breadth: The number of child nodes dependent on each main node.
/// - Returns: A tuple with root constaint and the containers.
func createDummyGraph(depth: Int, breadth: Int) -> (rootConstraint: MockPackageConstraint, containers: [MockPackageContainer]) {
    precondition(breadth >= 1, "Minimum breadth should be 1")
    // Create an array to hold all the containers.
    var containers = [MockPackageContainer]()
    // Create main nodes.
    for depthLevel in 0..<depth {
        // Create dependencies for for this node.
        let dependencies = (0 ..< (breadth-1)).map { breadthLevel -> (container: String, versionRequirement: VersionSetSpecifier) in
            let name = "\(depthLevel)-\(breadthLevel)"
            // Append the container for this node.
            containers += [MockPackageContainer(name: name, dependenciesByVersion: [v1: []])]
            return (name, v1Range)
        }
        // Compute the next node, we're going to add it to dependency of this node.
        let nextNode: [(container: String, versionRequirement: VersionSetSpecifier)]
        nextNode = (depthLevel != depth - 1) ? [(String(depthLevel + 1), v1Range)] : []
        // Create container for this node.
        containers += [MockPackageContainer(name: String(depthLevel), dependenciesByVersion: [v1: dependencies + nextNode])]
    }
    // Return the root constaint and containers.
    return (MockPackageConstraint(container: "0", versionRequirement: v1Range), containers)
}

#endif
