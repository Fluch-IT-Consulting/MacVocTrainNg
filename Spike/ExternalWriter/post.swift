import Foundation
DistributedNotificationCenter.default().postNotificationName(.init(CommandLine.arguments[1]), object: nil, userInfo: nil, deliverImmediately: true)
