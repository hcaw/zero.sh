import Foundation
import Path
import SwiftCLI

/// Name of workspace to parse, with children separated by ".".
typealias Workspace = [String]

enum ZeroValidationError: LocalizedError {
    /// Found a `./workspaces` directory in configuration path, but `workspace`
    /// parameter was not passed.
    case missingWorkspace

    /// Attempted to setup a workspace container (i.e. a directory containing a
    /// `./workspaces` directory), which is invalid.
    case workspaceIsParent

    /// The given path does not exist or is not a directory.
    case invalidDirectory(Path)

    public var errorDescription: String? {
        switch self {
        case .missingWorkspace:
            return "Missing required parameter 'workspace'."
        case .workspaceIsParent:
            return "Cannot setup parent of a workspace."
        case let .invalidDirectory(directoryPath):
            return "Not a directory: \(directoryPath)."
        }
    }
}

struct ZeroRunner {
    let configDirectory: Path
    let workspace: Workspace

    init(configDirectory: Path? = nil, workspace: Workspace) throws {
        let fallbackDirectories: [Path] = [
            Path.XDG.configHome.join("zero").join("dotfiles"),
            Path.home.join(".dotfiles"),
        ]
        self.configDirectory = configDirectory ?? fallbackDirectories.first { $0.isDirectory } ??
            fallbackDirectories.last!
        self.workspace = workspace
        try validate()
    }

    /// Run an executable with the given arguments, printing the command before
    /// running.
    func runTask(_ executable: String, _ arguments: String..., at directory: Path? = nil) throws {
        let escapedCommand: [String] = [executable] + arguments.map(Task.escapeArgument)
        Term.stdout <<< TTY.commandMessage(escapedCommand.joined(separator: " "))

        if let directory = directory, executable.hasPrefix(".") {
            // Process.launchPath doesn't seem to honor currentDirectoryPath
            // for relative executable paths.
            try Task.run(
                directory.join(executable).string,
                arguments: arguments,
                directory: directory.string
            )
        } else {
            try Task.run(executable, arguments: arguments, directory: directory?.string)
        }
    }
}

private extension ZeroRunner {
    /// Validates runner before use. Ensures given configDirectory and
    /// workspace are valid and exist on disk.
    func validate() throws {
        if !configDirectory.isDirectory {
            throw ZeroValidationError.invalidDirectory(configDirectory)
        }
        if workspace.isEmpty, configDirectory.join("workspaces").exists {
            throw ZeroValidationError.missingWorkspace
        }

        // Absolute path to each component of the workspace. For example, the
        // workspace "home.laptop" will contain the following paths:
        // "workspaces/home", "workspaces/home/laptop".
        let componentDirectories: [Path] = workspace.reduce(into: []) { result, name in
            let previous: Path = result.endIndex > 0 ? result[result.endIndex - 1] : configDirectory
            result.append(previous.join("workspaces").join(name))
        }

        if let missingDirectory = componentDirectories.first(where: { !$0.isDirectory }) {
            throw ZeroValidationError.invalidDirectory(missingDirectory)
        }
        if let lastDirectory = componentDirectories.last,
            lastDirectory.join("workspaces").isDirectory {
            throw ZeroValidationError.workspaceIsParent
        }
    }
}

private extension Task {
    /// Returns a shell escaped version of the given string.
    static func escapeArgument(_ argument: String) -> String {
        guard argument.rangeOfCharacter(from: .unsafeShellCharacters) != nil else {
            return argument
        }

        return String(
            format: "'%@'",
            argument.replacingOccurrences(of: "'", with: "'\"'\"", options: .literal, range: nil)
        )
    }
}

private extension CharacterSet {
    static var unsafeShellCharacters: CharacterSet {
        var characters: CharacterSet = .alphanumerics
        characters.insert(charactersIn: ",._+=:@%/-")
        characters.invert()
        return characters
    }
}
