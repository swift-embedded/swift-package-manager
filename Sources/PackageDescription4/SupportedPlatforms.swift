/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A platform that usually corresponds to an operating system such as
/// iOS, macOS, or Linux.
public struct Platform: Encodable {

    /// The name of the platform.
    fileprivate let name: String

    private init(name: String) {
        self.name = name
    }

    /// FIXME: add documentation
    public static let macOS: Platform = Platform(name: "macos")
    public static let iOS: Platform = Platform(name: "ios")
    public static let tvOS: Platform = Platform(name: "tvos")
    public static let watchOS: Platform = Platform(name: "watchos")
    public static let linux: Platform = Platform(name: "linux")
    public static let baremetal: Platform = Platform(name: "baremetal")
}

/// A platform that the Swift package supports.
///
/// By default, the Swift Package Manager assigns a predefined minimum deployment
/// version for each supported platforms unless you configure supported platforms using the `platforms`
/// API. This predefined deployment version is the oldest deployment target
/// version that the installed SDK supports for a given platform. One exception
/// to this rule is macOS, for which the minimum deployment target version
/// starts from 10.10. Packages can choose to configure the minimum deployment
/// target version for a platform by using the APIs defined in this struct. The
/// Swift Package Manager emits appropriate errors when an invalid value is
/// provided for supported platforms, such as an empty array, multiple declarations
/// for the same platform, or an invalid version specification.
///
/// The Swift Package Manager will emit an error if a dependency is not
/// compatible with the top-level package's deployment version. The deployment
/// target of a package's dependencies must be lower than or equal to the top-level package's
/// deployment target version for a particular platform.
public struct SupportedPlatform: Encodable {

    /// The platform.
    let platform: Platform

    /// The platform version.
    let version: String?

    /// Creates supported platform instance.
    init(platform: Platform, version: String? = nil) {
        self.platform = platform
        self.version = version
    }

    /// Configure the minimum deployment target version for the macOS platform.
    ///
    /// - Since: First available in PackageDescription 5.0
    ///
    /// - Parameter version: The minimum deployment target that the package supports.
    public static func macOS(_ version: SupportedPlatform.MacOSVersion) -> SupportedPlatform {
        return SupportedPlatform(platform: .macOS, version: version.version)
    }

    /// Configure the minimum deployment target version for the macOS platform
    /// using a version string.
    ///
    /// The version string must be a series of two or three dot-separated integers, such as "10.10" or "10.10.1".
    ///
    /// - Since: First available in PackageDescription 5.0
    ///
    /// - Parameter versionString: The minimum deployment target as a string representation of two or three dot-separated integers, such as "10.10.1".
    public static func macOS(_ versionString: String) -> SupportedPlatform {
        return SupportedPlatform(platform: .macOS, version: SupportedPlatform.MacOSVersion(string: versionString).version)
    }

    /// Configure the minimum deployment target version for the iOS platform.
    ///
    /// - Since: First available in PackageDescription 5.0
    ///
    /// - Parameter version: The minimum deployment target that the package supports.
    public static func iOS(_ version: SupportedPlatform.IOSVersion) -> SupportedPlatform {
        return SupportedPlatform(platform: .iOS, version: version.version)
    }

    /// Configure the minimum deployment target version for the iOS platform
    /// using a custom version string.
    ///
    /// The version string must be a series of two or three dot-separated integers, such as "8.0" or "8.0.1".
    ///
    /// - Since: First available in PackageDescription 5.0
    ///
    /// - Parameter versionString: The minimum deployment target as a string representation of two or three dot-separated integers, such as "8.0.1".
    public static func iOS(_ versionString: String) -> SupportedPlatform {
        return SupportedPlatform(platform: .iOS, version: SupportedPlatform.IOSVersion(string: versionString).version)
    }

    /// Configure the minimum deployment target version for the tvOS platform.
    ///
    /// - Since: First available in PackageDescription 5.0
    ///
    /// - Parameter version: The minimum deployment target that the package supports.
    public static func tvOS(_ version: SupportedPlatform.TVOSVersion) -> SupportedPlatform {
        return SupportedPlatform(platform: .tvOS, version: version.version)
    }

    /// Configure the minimum deployment target version for the tvOS platform
    /// using a custom version string.
    ///
    /// The version string must be a series of two or three dot-separated integers,such as "9.0" or "9.0.1".
    ///
    /// - Since: First available in PackageDescription 5.0
    ///
    /// - Parameter versionString: The minimum deployment target as a string representation of two or three dot-separated integers, such as "9.0.1".
    public static func tvOS(_ versionString: String) -> SupportedPlatform {
        return SupportedPlatform(platform: .tvOS, version: SupportedPlatform.TVOSVersion(string: versionString).version)
    }

    /// Configure the minimum deployment target version for the watchOS platform.
    ///
    /// - Since: First available in PackageDescription 5.0
    ///
    /// - Parameter version: The minimum deployment target that the package supports.
    public static func watchOS(_ version: SupportedPlatform.WatchOSVersion) -> SupportedPlatform {
        return SupportedPlatform(platform: .watchOS, version: version.version)
    }

    /// Configure the minimum deployment target version for the watchOS platform
    /// using a custom version string.
    ///
    /// The version string must be a series of two or three dot-separated integers, such as "2.0" or "2.0.1".
    ///
    /// - Since: First available in PackageDescription 5.0
    ///
    /// - Parameter versionString: The minimum deployment target as a string representation of two or three dot-separated integers, such as "2.0.1".
    public static func watchOS(_ versionString: String) -> SupportedPlatform {
        return SupportedPlatform(platform: .watchOS, version: SupportedPlatform.WatchOSVersion(string: versionString).version)
    }

    /// The BareMetal platform.
    public static func baremetal() -> SupportedPlatform {
        return SupportedPlatform(platform: .baremetal)
    }
}

/// An extension to the SupportedPlatform struct that defines major platform versions.
extension SupportedPlatform {
    /// The macOS version.
    public struct MacOSVersion: Encodable, AppleOSVersion {
        fileprivate static let name = "macOS"
        fileprivate static let minimumMajorVersion = 10

        /// The underlying version representation.
        let version: String

        fileprivate init(uncheckedVersion version: String) {
            self.version = version
        }

        /// The value that represents macOS 10.10.
        ///
        /// - Since: First available in PackageDescription 5.0
        public static let v10_10: MacOSVersion = .init(string: "10.10")

        /// The value that represents macOS 10.11.
        ///
        /// - Since: First available in PackageDescription 5.0
        public static let v10_11: MacOSVersion = .init(string: "10.11")

        /// The value that represents macOS 10.12.
        ///
        /// - Since: First available in PackageDescription 5.0
        public static let v10_12: MacOSVersion = .init(string: "10.12")

        /// The value that represents macOS 10.13.
        ///
        /// - Since: First available in PackageDescription 5.0
        public static let v10_13: MacOSVersion = .init(string: "10.13")

        /// The value that represents macOS 10.14.
        ///
        /// - Since: First available in PackageDescription 5.0
        public static let v10_14: MacOSVersion = .init(string: "10.14")

        /// The value that represents macOS 10.15.
        ///
        /// - Since: First available in PackageDescription 5.1
        @available(_PackageDescription, introduced: 5.1)
        public static let v10_15: MacOSVersion = .init(string: "10.15")
    }

    public struct TVOSVersion: Encodable, AppleOSVersion {
        fileprivate static let name = "tvOS"
        fileprivate static let minimumMajorVersion = 9

        /// The underlying version representation.
        let version: String

        fileprivate init(uncheckedVersion version: String) {
            self.version = version
        }

        /// The value that represents tvOS 9.0.
        ///
        /// - Since: First available in PackageDescription 5.0
        public static let v9: TVOSVersion = .init(string: "9.0")

        /// The value that represents tvOS 10.0.
        ///
        /// - Since: First available in PackageDescription 5.0
        public static let v10: TVOSVersion = .init(string: "10.0")

        /// The value that represents tvOS 11.0.
        ///
        /// - Since: First available in PackageDescription 5.0
        public static let v11: TVOSVersion = .init(string: "11.0")

        /// The value that represents tvOS 12.0.
        ///
        /// - Since: First available in PackageDescription 5.0
        public static let v12: TVOSVersion = .init(string: "12.0")

        /// The value that represents tvOS 13.0.
        ///
        /// - Since: First available in PackageDescription 5.1
        @available(_PackageDescription, introduced: 5.1)
        public static let v13: TVOSVersion = .init(string: "13.0")
    }

    public struct IOSVersion: Encodable, AppleOSVersion {
        fileprivate static let name = "iOS"
        fileprivate static let minimumMajorVersion = 2

        /// The underlying version representation.
        let version: String

        fileprivate init(uncheckedVersion version: String) {
            self.version = version
        }

        /// The value that represents iOS 8.0.
        ///
        /// - Since: First available in PackageDescription 5.0
        public static let v8: IOSVersion = .init(string: "8.0")

        /// The value that represents iOS 9.0.
        ///
        /// - Since: First available in PackageDescription 5.0
        public static let v9: IOSVersion = .init(string: "9.0")

        /// The value that represents iOS 10.0.
        ///
        /// - Since: First available in PackageDescription 5.0
        public static let v10: IOSVersion = .init(string: "10.0")

        /// The value that represents iOS 11.0.
        ///
        /// - Since: First available in PackageDescription 5.0
        public static let v11: IOSVersion = .init(string: "11.0")

        /// The value that represents iOS 12.0.
        ///
        /// - Since: First available in PackageDescription 5.0
        public static let v12: IOSVersion = .init(string: "12.0")

        /// The value that represents iOS 13.0.
        ///
        /// - Since: First available in PackageDescription 5.1
        @available(_PackageDescription, introduced: 5.1)
        public static let v13: IOSVersion = .init(string: "13.0")
    }

    public struct WatchOSVersion: Encodable, AppleOSVersion {
        fileprivate static let name = "watchOS"
        fileprivate static let minimumMajorVersion = 2

        /// The underlying version representation.
        let version: String

        fileprivate init(uncheckedVersion version: String) {
            self.version = version
        }

        /// The value that represents watchOS 2.0.
        ///
        /// - Since: First available in PackageDescription 5.0
        public static let v2: WatchOSVersion = .init(string: "2.0")

        /// The value that represents watchOS 3.0.
        ///
        /// - Since: First available in PackageDescription 5.0
        public static let v3: WatchOSVersion = .init(string: "3.0")

        /// The value that represents watchOS 4.0.
        ///
        /// - Since: First available in PackageDescription 5.0
        public static let v4: WatchOSVersion = .init(string: "4.0")

        /// The value that represents watchOS 5.0.
        ///
        /// - Since: First available in PackageDescription 5.0
        public static let v5: WatchOSVersion = .init(string: "5.0")

        /// The value that represents watchOS 6.0.
        ///
        /// - Since: First available in PackageDescription 5.1
        @available(_PackageDescription, introduced: 5.1)
        public static let v6: WatchOSVersion = .init(string: "6.0")
    }
}

fileprivate protocol AppleOSVersion {
    static var name: String { get }
    static var minimumMajorVersion: Int { get }
    init(uncheckedVersion: String)
}

fileprivate extension AppleOSVersion {
    init(string: String) {
        // Perform a quick validation.
        let components = string.split(separator: ".", omittingEmptySubsequences: false).map({ UInt($0) })
        var error = components.compactMap({ $0 }).count != components.count
        error = error || !(components.count == 2 || components.count == 3) || ((components[0] ?? 0) < Self.minimumMajorVersion)
        if error {
            errors.append("invalid \(Self.name) version string: \(string)")
        }

        self.init(uncheckedVersion: string)
    }
}
