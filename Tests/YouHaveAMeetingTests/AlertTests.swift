import Foundation
import Testing
@testable import YouHaveAMeetingCore

@Suite("EscalationSchedule")
struct EscalationScheduleTests {
    @Test("first chime is immediate")
    func firstChimeIsImmediate() {
        #expect(EscalationSchedule.offset(forChime: 0) == 0)
        #expect(EscalationSchedule.gap(beforeChime: 0) == 0)
    }

    @Test("follows the documented ramp")
    func ramp() {
        #expect(EscalationSchedule.offset(forChime: 1) == 15)
        #expect(EscalationSchedule.offset(forChime: 2) == 30)
        #expect(EscalationSchedule.offset(forChime: 3) == 60)
    }

    @Test("repeats every 60s once the ramp is exhausted")
    func repeatsForever() {
        #expect(EscalationSchedule.offset(forChime: 4) == 120)
        #expect(EscalationSchedule.offset(forChime: 5) == 180)
        #expect(EscalationSchedule.gap(beforeChime: 4) == 60)
        #expect(EscalationSchedule.gap(beforeChime: 99) == 60)
    }

    @Test("gaps always accumulate to the offset")
    func gapsAccumulate() {
        var total: TimeInterval = 0
        for index in 0 ... 10 {
            total += EscalationSchedule.gap(beforeChime: index)
            #expect(total == EscalationSchedule.offset(forChime: index))
        }
    }
}

@Suite("LaunchOptions")
struct LaunchOptionsTests {
    @Test("defaults to no test alert")
    func defaults() {
        let options = LaunchOptions(arguments: ["/path/to/app"])
        #expect(!options.testAlert)
        #expect(options.testAlertStyle == .takeover)
    }

    @Test("--test-alert selects the takeover by default")
    func takeover() {
        let options = LaunchOptions(arguments: ["/path/to/app", "--test-alert"])
        #expect(options.testAlert)
        #expect(options.testAlertStyle == .takeover)
    }

    @Test("--banner downgrades the test alert")
    func banner() {
        let options = LaunchOptions(arguments: ["/path/to/app", "--test-alert", "--banner"])
        #expect(options.testAlert)
        #expect(options.testAlertStyle == .banner)
    }
}

@Suite("Diagnostic flags")
struct DiagnosticFlagTests {
    @Test("--list-meetings is off unless asked for")
    func defaultOff() {
        #expect(!LaunchOptions(arguments: ["/app"]).listMeetings)
    }

    @Test("--list-meetings withholds titles unless --verbose")
    func verbosity() {
        let quiet = LaunchOptions(arguments: ["/app", "--list-meetings"])
        #expect(quiet.listMeetings)
        #expect(!quiet.verbose)

        let loud = LaunchOptions(arguments: ["/app", "--list-meetings", "--verbose"])
        #expect(loud.verbose)
    }
}
