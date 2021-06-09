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
import Combine

/*:
 ## Sandbox
 
 A place where you can build your sand castles 🏖.
*/
private class MutablePropertySubscriber<Input>: Subscriber {
    typealias Input = Input
    typealias Failure = Never

    private let property: MutableProperty<Input>
    private let disposable = CompositeDisposable()
    private var isUpdatingSubject = false
    private var isUpdatingProperty = false

    init(_ property: MutableProperty<Input>, subject: CurrentValueSubject<Input, Never>) {
        self.property = property

        disposable += property.signal.observeValues { [weak self, disposable, weak subject] newValue in
            guard let self = self else {
                disposable.dispose()
                return
            }
            guard !self.isUpdatingProperty else {
                return
            }
            self.isUpdatingSubject = true
            subject?.send(newValue)
            self.isUpdatingSubject = false
        }
    }

    func receive(subscription: Subscription) {
        subscription.request(.unlimited)
    }

    func receive(_ input: Input) -> Subscribers.Demand {
        if !isUpdatingSubject {
            isUpdatingProperty = true
            property.value = input
            isUpdatingProperty = false
        }
        return .unlimited
    }

    func receive(completion: Subscribers.Completion<Never>) {
        disposable.dispose()
    }
}

extension MutableProperty {
    func subject() -> CurrentValueSubject<Value, Never> {
        let subject = CurrentValueSubject<Value, Never>(value)
        // self IS retained by the subscriber and therefore by the subject. Expected.
        // subject is only weakly retained by `MutablePropertySubscriber` so should not
        // create a retain cycle.
        subject.subscribe(MutablePropertySubscriber(self, subject: subject))
        return subject
    }
}

func main() {
    let property = MutableProperty(1)

    var subject: CurrentValueSubject<Int, Never>? = property.subject()
    weak var weakSubject = subject

    weakSubject?.value == 1
    var values = [Int]()
    let cancellable = weakSubject?.sink(receiveValue: { (value) in
        values.append(value)
    })

    property.value = 2
    weakSubject?.value == 2
    values == [1, 2]

    weakSubject?.value = 3
    property.value ==  3
    values == [1, 2, 3]

    subject = nil
    cancellable?.cancel()

    // Unexpected, returns false!
    weakSubject == nil
}

main()

