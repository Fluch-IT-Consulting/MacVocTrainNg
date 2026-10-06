import Testing

@testable import VocabCore

struct StepsTests {
    @Test func againResetsTheSteps() {
        var steps = Steps(count: 2, required: 3)
        steps.apply(.again)
        #expect(steps.count == 0)
        #expect(!steps.areEnough)
    }

    @Test func hardKeepsTheStep() {
        var steps = Steps(count: 2, required: 3)
        steps.apply(.hard)
        #expect(steps.count == 2)
        #expect(!steps.areEnough)
    }

    @Test func goodAddsOneStep() {
        var steps = Steps(count: 1, required: 3)
        steps.apply(.good)
        #expect(steps.count == 2)
        #expect(!steps.areEnough)
        steps.apply(.good)
        #expect(steps.count == 3)
        #expect(steps.areEnough)
    }

    @Test func easyCollectsAllStepsAtOnce() {
        var steps = Steps(required: 3)
        steps.apply(.easy)
        #expect(steps.count == 3)
        #expect(steps.areEnough)
    }

    @Test(arguments: [0, -2])
    func atLeastOneStepIsRequired(required: Int) {
        var steps = Steps(required: required)
        #expect(steps.required == 1)
        #expect(!steps.areEnough)
        steps.apply(.hard)
        #expect(!steps.areEnough)
        steps.apply(.good)
        #expect(steps.areEnough)
    }
}
