//
//  AppDelegate.swift
//  TestApp
//
//  Created by Gustavo Ambrozio on 6/9/21.
//  Copyright © 2021 GitHub. All rights reserved.
//

import Cocoa
import ReactiveSwift
import Combine

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
		let property = MutableProperty(1)

		var subject: CurrentValueSubject<Int, Never>? = property.subject()
		weak var weakSubject = subject

		print("success? \(weakSubject?.value == 1)")
		var values = [Int]()
		let cancellable = weakSubject?.sink(receiveValue: { (value) in
			values.append(value)
		})

		property.value = 2
		print("success? \(weakSubject?.value == 2)")
		print("success? \(values == [1, 2])")

		weakSubject?.value = 3
		print("success? \(property.value ==  3)")
		print("success? \(values == [1, 2, 3])")

		subject = nil
		cancellable?.cancel()

		// Unexpected, returns false!
		print("success? \(weakSubject == nil)")
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
}


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
		let p2 = MutablePropertySubscriber(self, subject: subject)
		// MG: In the labs we proved that subject was 1 here so there is nothing funky with p2.
		// The leak shows up in the innards of subscribe. We validated and proved using instruments
		// that there are bunch of leaks here.

		// at this point the retain count of subject is 1
		subject.subscribe(p2)
		// now the retain count is 2.
		return subject
	}
}
