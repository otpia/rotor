import SwiftUI

/// Abstract representation of the position of an element along an Axis. Used to abstract computations of the positions across vertical and horizontal stacks.
nonisolated protocol AxisPosition: Equatable, Sendable {
  associatedtype Preference: PreferenceKey where Preference.Value == Self
  
  init(_ rect: CGRect)
  
  var min: CGFloat { get }
  var max: CGFloat { get }
  
  func contains(_ val: CGFloat) -> Bool
  
  var span: CGFloat { get }
}

extension AxisPosition {
  /// Whether the value is within the element alongside the specific axis.
  func contains(_ val: CGFloat) -> Bool {
    return min <= val && val <= max
  }
  
  /// The length of the elemement alongside the specific axis.
  var span: CGFloat {
    return max - min
  }
}

nonisolated struct VerticalPositionPreferenceKey: PreferenceKey {
  static var defaultValue: VerticalPosition { .init(.zero) }
  
  static func reduce(value: inout VerticalPosition, nextValue: () -> VerticalPosition) {
    value = nextValue()
  }
}

nonisolated struct VerticalPosition: AxisPosition {
  typealias Preference = VerticalPositionPreferenceKey
  
  let min: CGFloat
  let max: CGFloat
  
  init(_ rect: CGRect) {
    min = rect.minY
    max = rect.maxY
  }
}

nonisolated struct HorizontalPositionPreferenceKey: PreferenceKey {
  static var defaultValue: HorizontalPosition { .init(.zero) }
  
  static func reduce(value: inout HorizontalPosition, nextValue: () -> HorizontalPosition) {
    value = nextValue()
  }
}

nonisolated struct HorizontalPosition: AxisPosition {
  typealias Preference = HorizontalPositionPreferenceKey
  
  let min: CGFloat
  let max: CGFloat
  
  init(_ rect: CGRect) {
    min = rect.minX
    max = rect.maxX
  }
}
