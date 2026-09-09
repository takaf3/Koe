import Foundation

enum InsertionPolicy {
    enum Decision: Equatable {
        case insert, needsAccessibility, noTarget, targetClosed, differentApplication, secureField
    }

    // Accessibility element identity is deliberately not an input. Web editors
    // can replace their AX nodes while the OS keyboard focus remains in the field.
    static func decision(trusted: Bool, targetPID: pid_t?, foregroundPID: pid_t?,
                         targetTerminated: Bool, secureField: Bool) -> Decision {
        guard trusted else { return .needsAccessibility }
        guard let targetPID else { return .noTarget }
        guard !targetTerminated else { return .targetClosed }
        guard targetPID == foregroundPID else { return .differentApplication }
        guard !secureField else { return .secureField }
        return .insert
    }
}
