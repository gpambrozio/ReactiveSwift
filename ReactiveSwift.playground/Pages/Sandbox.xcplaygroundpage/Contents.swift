/*:
 > # IMPORTANT: To use `ReactiveSwift.playground`, please:
 
 1. Retrieve the project dependencies using one of the following terminal commands from the ReactiveSwift project root directory:
    - `git submodule update --init`
 **OR**, if you have [Carthage](https://github.com/Carthage/Carthage) installed
    - `carthage checkout`
 1. Open `ReactiveSwift.xcworkspace`
 1. Build `ReactiveSwift-macOS` scheme
 1. Finally open the `ReactiveSwift.playground`
 1. Choose `View > Show Debug Area`
 */

import ReactiveSwift
import Foundation

/**********************************************
 These have all been copied from our project
 **********************************************/

func performScopedOperation(_ description: String, active: Bool = true, _ sideEffect: () throws -> ()) rethrows {
    guard active else { return }
//    print("Executing \(description)")
    try sideEffect()
}

/// This came from one of the comments here: https://stackoverflow.com/a/34685535/754013
extension DispatchQueue {
    class var currentLabel: String {
        return String(validatingUTF8: __dispatch_queue_get_label(nil)) ?? "unknown"
    }
}

extension Signal where Error == Never {
    func scanToProperty<U>(
        initialValue: U,
        nextPartialResult: @escaping (inout U, Value) -> Void
    ) -> Property<U> {
        return Property.init(
            initial: initialValue,
            then: scan(into: initialValue, nextPartialResult)
        )
    }
}

extension SignalProducer {
    static func sideEffectOnly(_ sideEffect: @escaping () -> Void) -> SignalProducer {
        return SignalProducer { observer, disposable in
            sideEffect()
            observer.sendCompleted()
        }
    }
}

public struct MtSideEffect {
    public let mtCall_sideEffect: () -> Void
    public init(mtCall_sideEffect: @escaping () -> Void) {
        self.mtCall_sideEffect = mtCall_sideEffect
    }
}

/*:
 ## Sandbox
 
 A place where you can build your sand castles 🏖.
*/
performScopedOperation("Bad Signal observer", active: false) {
    class BadObserver {
        init(_ signal: Signal<String, Never>) {
            signal.observeValues {
                print("Observer saw value \($0)")
            }
        }
    }

    let (signal, observer) = Signal<String, Never>.pipe()

    var myObserver: BadObserver? = BadObserver(signal)

    observer.send(value: "Should see this event")
    myObserver = nil
    observer.send(value: "Would expect not to see it again")
}

performScopedOperation("Good Signal observer", active: false) {
    class GoodObserver {
        private let (lifetime, token) = Lifetime.make()
        init(_ signal: Signal<String, Never>) {
            lifetime += signal.observeValues {
                print("Observer saw value \($0)")
            }
        }
    }

    let (signal, observer) = Signal<String, Never>.pipe()

    var myObserver: GoodObserver? = GoodObserver(signal)

    observer.send(value: "Should see this event")
    myObserver = nil
    observer.send(value: "Would expect not to see it again")
}

performScopedOperation("Difference between start(on:) and observe(on:)", active: false) {
    let (lifetime, token) = Lifetime.make()
    let observationScheduler = QueueScheduler(name: "observationScheduler")
    let startScheduler = QueueScheduler(name: "startScheduler")

    let producer = SignalProducer<String, Never> { observer, lifetime in
        print("Start is running on \(DispatchQueue.currentLabel)")
        observer.send(value: "0")
    }
    lifetime += producer
        .observe(on: observationScheduler)
        .start(on: startScheduler)
        .startWithValues { _ in
            print("Observation is running on \(DispatchQueue.currentLabel)")
        }

    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
}

performScopedOperation("SignalProducers don't end when getting out of scope!", active: false) {
    let disposable = CompositeDisposable()
    performScopedOperation("Inner scope") {
        let producer = SignalProducer<String, Never> { observer, lifetime in
            var i = 1
            let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { (_) in
                observer.send(value: "\(i)")
                i += 1
            })
            lifetime.observeEnded {
                timer.invalidate()
            }
        }
        disposable += producer
            .on { print("Value: \($0)") }
            .start()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.1))
    }

    print("End of scope")
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 5))
    disposable.dispose()
}

performScopedOperation("SignalProducer with a lifetime. Good boy!", active: false) {
    performScopedOperation("Inner scope") {
        let (lifetime, token) = Lifetime.make()
        let producer = SignalProducer<String, Never> { observer, lifetime in
            var i = 1
            let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { (_) in
                observer.send(value: "\(i)")
                i += 1
            })
            lifetime.observeEnded {
                timer.invalidate()
            }
        }
        lifetime += producer
            .on { print("Value: \($0)") }
            .start()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.1))
    }

    print("End of scope")
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 5))
}

performScopedOperation("Starting a producer twice and being OK with it", active: false) {
    let property = MutableProperty("first")
    let propertyProducer = property.producer

    propertyProducer
        .map { "This is the \($0) value" }
        .startWithValues {
            print("Value: \($0)")
        }

    propertyProducer
        .startWithValues {
            print("Value: \($0)")
        }

    property.value = "second"
}

performScopedOperation("Starting a producer twice and getting unexpected results", active: false) {
    let authenticateAction = Action<(), Bool, Never> {
        return SignalProducer(value: true).delay(2, on: QueueScheduler())
    }
    let authenticationProducer = SignalProducer<Bool, Never> { observer, lifetime in
        let producer = authenticateAction.apply(()).flatMapError { _ in SignalProducer(value: false) }
        lifetime += producer.start(observer)
    }

    authenticationProducer
        .map { "Mapped value: \($0)" }
        .startWithValues {
            print("Mapped Value: \($0)")
        }

    authenticationProducer
        .startWithValues {
            print("Original value: \($0)")
        }
}

performScopedOperation("Starting a producer twice and really being ok with it", active: false) {
    let authenticateAction = Action<(), Bool, Never> {
        return SignalProducer(value: true).delay(2, on: QueueScheduler())
    }
    let authenticationProducer = SignalProducer<Bool, Never> { observer, lifetime in
        let producer = authenticateAction.apply(()).flatMapError { _ in SignalProducer(value: false) }
        lifetime += producer.start(observer)
    }
    .replayLazily(upTo: Int.max)

    authenticationProducer
        .map { "Mapped value: \($0)" }
        .startWithValues {
            print("Mapped Value: \($0)")
        }

    authenticationProducer
        .startWithValues {
            print("Original value: \($0)")
        }
}

performScopedOperation("Don't use Action as a closure replacement", active: false) {
    // If this is supposed to be inside a CocoaAction then it's OK.
    // Otherwise you should pass a simple closure or, if you want to make sure
    // it runs on the main thread, use our `MtSideEffect` struct
    let routeMeOutaHereForUI = Action<(), Never, Never> { Void in
        return SignalProducer.sideEffectOnly {
//             router.mt_handle(action: .close, animated: true)
        }.start(on: UIScheduler())
    }

    // Using `MtSideEffect`
    let routeMeOutaHereForEverythingElse = MtSideEffect(mtCall_sideEffect: {
//        router.mt_handle(action: .close, animated: true)
    })
}

performScopedOperation("Actions should not modify any other state", active: false) {
    let isSomethingEnabled = MutableProperty(false)
    let enableDisableAction = Action<(), Bool, Never>(state: isSomethingEnabled) { enabled, Void in
        isSomethingEnabled.value = !enabled
        return SignalProducer(value: !enabled)
    }

    enableDisableAction
        .values
        .observeValues { enabled in
            print("Did \(enabled ? "enable" : "disable")")
    }

    enableDisableAction.apply().start()
    enableDisableAction.apply().start()
}

performScopedOperation("Modifying state should be a side-effect", active: false) {
    let isSomethingEnabled = MutableProperty(false)
    let enableDisableAction = Action<(), Bool, Never>(state: isSomethingEnabled) { enabled, Void in
        SignalProducer(value: !enabled)
    }

    // Update state
    isSomethingEnabled <~ enableDisableAction.values

    enableDisableAction
        .values
        .observeValues { enabled in
            print("Did \(enabled ? "enable" : "disable")")
    }

    enableDisableAction.apply().start()
    enableDisableAction.apply().start()
}

performScopedOperation("Better way to use action in this case", active: false) {
    let enableDisableAction = Action<(), (), Never> { Void in
        SignalProducer(value: ())
    }
    let isSomethingEnabled: Property<Bool> = enableDisableAction
        .values
        .scanToProperty(initialValue: false) { currentValue, Void in
            currentValue = !currentValue
        }

    isSomethingEnabled
        .signal
        .observeValues { enabled in
            print("Did \(enabled ? "enable" : "disable")")
        }

    enableDisableAction.apply().start()
    enableDisableAction.apply().start()
}

performScopedOperation("Even better way to use action in this case", active: false) {
    let enableDisableAction = Action<(), Never, Never> { Void in
        SignalProducer.empty
    }
    let isSomethingEnabled: Property<Bool> = enableDisableAction
        .completed
        .scanToProperty(initialValue: false) { currentValue, Void in
            currentValue = !currentValue
        }

    isSomethingEnabled
        .signal
        .observeValues { enabled in
            print("Did \(enabled ? "enable" : "disable")")
        }

    enableDisableAction.apply().start()
    enableDisableAction.apply().start()
}

performScopedOperation("What to return on an Action", active: true) {
    enum MyError: Error { case whatever }

    // Dubious of what to check for errors? Should we just check for a `false` value?
    // Should we check for failed events? Both?
    let actionThatCanFail_NoNo = Action<(), Bool, MyError> {
        return SignalProducer { observer, lifetime in
            guard true else {   // Something went wrong
                observer.send(error: .whatever)
            }
            // The only value it sends is `true`, so why have it as a bool at all?
            // The called does not know this so it gets confused on how to use this
            observer.send(value: true)
            observer.sendCompleted()
        }
    }

    // This is better. The caller can guess that we either get a value of true or
    // false depending on the result. No error is ever possible
    // It's better but we lose some information about the error and if we want to
    // log or show a better message to the user we don't have anything to use.
    let actionThatCanFail_Yes = Action<(), Bool, Never> {
        return SignalProducer { observer, lifetime in
            guard true else {   // Something went wrong
                observer.send(value: false)
                observer.sendCompleted()
            }
            observer.send(value: true)
            observer.sendCompleted()
        }
    }

    // This is even better. We can guess that when it completes it succeeded and if
    // something goes wrong we get an error that can be more descriptive that just
    // a `false`.
    let actionThatCanFail_Better = Action<(), Never, MyError> {
        return SignalProducer { observer, lifetime in
            guard true else {   // Something went wrong
                observer.send(error: .whatever)
            }
            observer.sendCompleted()
        }
    }
}

performScopedOperation("Actions should perform their work in the producer", active: false) {
    let isLoggedIn = MutableProperty(false)
    let logInAndOutAction = Action<(), Bool, Never>(state: isLoggedIn) { isLoggedIn, Void in
        SignalProducer(value: !isLoggedIn)
    }
    logInAndOutAction
        .values
        .observeValues { shouldLogIn in
            // Do network request here.
            print("Logging \(shouldLogIn ? "in" : "out")")
            Thread.sleep(forTimeInterval: 1)
        }

    // Update state
    isLoggedIn <~ logInAndOutAction.values

    logInAndOutAction.apply().start()
    logInAndOutAction.apply().start()
}

performScopedOperation("Actions performing their work in the producer", active: false) {
    let isLoggedIn = MutableProperty(false)
    let logInAndOutAction = Action<(), Bool, Never>(state: isLoggedIn) { isLoggedIn, Void in
        SignalProducer { observer, lifetime in
            // Do network request here (simulating with a delay
            print("Logging \(isLoggedIn ? "out" : "in")")
            Timer.scheduledTimer(withTimeInterval: 1, repeats: false, block: { _ in
                observer.send(value: !isLoggedIn)
                observer.sendCompleted()
            })
        }
    }
    logInAndOutAction
        .disabledErrors
        .observeValues { print("was disabled...") }
    logInAndOutAction
        .values
        .observeValues { shouldLogIn in
            print("Did log \(shouldLogIn ? "in" : "out")")
        }

    // Update state
    isLoggedIn <~ logInAndOutAction.values
    logInAndOutAction.isExecuting

    logInAndOutAction.apply().start()
    logInAndOutAction.apply().start()
}

performScopedOperation("Using signal or producer on a Property", active: false) {
    let property = MutableProperty(false)

    property
        .signal
        .observeValues { print("signal   value: \($0)") }

    property
        .producer
        .startWithValues { print("producer value: \($0)") }

    property.value = true
    property.value = false
}

performScopedOperation("Using flatMap when map will do", active: false) {
    let producer = SignalProducer.init(value: "Hello")

    // Is OK but way more complicated
    producer.flatMap(.latest) { SignalProducer(value: "\($0) there") }.startWithValues { print($0) }
    producer.map { "\($0) there" }.startWithValues { print($0) }
}

performScopedOperation("Using flatMapError when mapError will do", active: false) {
    enum MyError: Error { case whatever, mistake }

    let producer = SignalProducer<Never, MyError>.init(error: MyError.whatever)

    // Is OK but way more complicated
    producer.flatMapError { _ in SignalProducer(error: MyError.mistake) }.startWithFailed { print($0) }
    producer.mapError { _ in MyError.mistake }.startWithFailed { print($0) }
}

performScopedOperation("Using filterMap when you really want to filter", active: false) {
    let numbers = SignalProducer.init(1...6)

    // Is OK but more complicated and doesn't tell you what exactly it's doing
    numbers.filterMap { $0 % 2 == 0 ? $0 : nil }.startWithValues { print($0) }
    numbers.filter { $0 % 2 == 0 }.startWithValues { print($0) }

    print("")

    // Even when you actually map inside it's better as 2 operations to make the intention clearer
    numbers.filterMap { $0 % 2 == 0 ? $0 * 2 : nil }.startWithValues { print($0) }
    numbers.filter { $0 % 2 == 0 }.map { $0 * 2 }.startWithValues { print($0) }
}

performScopedOperation("Difference between filter and skip", active: false) {
    let numbers = SignalProducer.init(1...6)

    numbers.filter { $0 % 2 == 1 }.startWithValues { print($0) }
    print("")
    numbers.skip { $0 % 2 == 1 }.startWithValues { print($0) }
    // The declaration of skip is `skip(while:)`, meaning it skips only
    // while the closure returns true and then forwards everything.
    // Not the same as filter
}

performScopedOperation("Difference between observe and on (for Signals)", active: true) {
    let signal = Signal<String, Never>.init { observer, lifetime in
        var i = 1
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { _ in
            observer.send(value: "\(i)")
            i += 1
        })
        lifetime.observeEnded {
            timer.invalidate()
        }
    }


}

performScopedOperation("flatMap strategies", active: false) {
    let outerProducer = SignalProducer(value: 0).merge(with: SignalProducer.timer(interval: .milliseconds(800), on: QueueScheduler()).scan(0, { (prev, _) in prev + 1 }).take(first: 4))
    let innerProducer = SignalProducer(value: 0).merge(with: SignalProducer.timer(interval: .milliseconds(500), on: QueueScheduler()).scan(0, { (prev, _) in prev + 1 }).take(first: 6))

    func testFlatMap(_ strategy: ReactiveSwift.FlattenStrategy, _ description: String) {
        print("Testing strategy \(description)")

        let (lifetime, token) = Lifetime.make()
        let startOfTest = Date()

        let flattenedProducer = outerProducer.flatMap(strategy) { outerCount in
            innerProducer.map { (outerCount, $0, Date().timeIntervalSince(startOfTest)) }
        }.collect()

        let result = flattenedProducer.last()
        switch result! {
        case .failure: break   // Will not happen in this case
        case .success(let value):
            var grid = [Int: [(Int, TimeInterval)]]()
            for (outer, inner, time) in value {
                if grid[outer] == nil {
                    grid[outer] = []
                }
                grid[outer]!.append((inner, time))
            }

            for outer in grid.keys.sorted() {
                let line = grid[outer]!
                var lineOutput = ""
                var lastTime: TimeInterval = 0
                for (inner, time) in line {
                    let elapsed = time - lastTime
                    lineOutput += String(repeating: " ", count: max(0, Int(10 * elapsed + 0.5))) + "\(outer)-\(inner)"
                    lastTime = time + 0.3
                }
                print(lineOutput)
            }
        }

        print("")
    }

    testFlatMap(.merge, "merge: any value sent by any of the inner streams is forwarded immediately to the flattened stream of values")
    testFlatMap(.latest, "latest: only values from the latest inner stream are sent by the stream of streams")
    testFlatMap(.concat, "concat: only values from one inner stream are forwarded at a time, in the order the inner streams are received")
    testFlatMap(.concurrent(limit: 2), "concurrent(2): any value sent by any of the inner streams on the fly is forwarded immediately to the flattened stream of values")
    testFlatMap(.race, "race: events from the first inner stream that sends an event. Any other in-flight inner streams is disposed of when the winning inner stream is determined.")
}

