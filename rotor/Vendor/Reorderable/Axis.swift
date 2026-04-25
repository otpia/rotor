import Foundation

nonisolated protocol ContainerAxis: Sendable {
  associatedtype Position: AxisPosition
  
  static func project(point: CGPoint) -> CGFloat
  static func project(maybePoint: CGPoint?) -> CGFloat?
  static func project(size: CGSize) -> CGFloat
  static func asPoint(value: CGFloat) -> CGPoint
  static func asSize(value: CGFloat) -> CGSize
}

nonisolated struct VerticalContainerAxis: ContainerAxis {
  public typealias Position = VerticalPosition
  
  static func project(point: CGPoint) -> CGFloat {
    point.y
  }
  
  static func project(maybePoint: CGPoint?) -> CGFloat? {
    maybePoint?.y
  }
  
  static func project(size: CGSize) -> CGFloat {
    .init(size.height)
  }
  
  static func asPoint(value: CGFloat) -> CGPoint {
    .init(x: 0, y: value)
  }
  
  static func asSize(value: CGFloat) -> CGSize {
    .init(width: 0, height: value)
  }
}

nonisolated struct HorizontalContainerAxis: ContainerAxis {
  public typealias Position = HorizontalPosition
  
  static func project(point: CGPoint) -> CGFloat {
    point.x
  }
  
  static func project(maybePoint: CGPoint?) -> CGFloat? {
    maybePoint?.x
  }
  
  static func project(size: CGSize) -> CGFloat {
    .init(size.width)
  }
  
  static func asPoint(value: CGFloat) -> CGPoint {
    .init(x: value, y: 0)
  }
  
  static func asSize(value: CGFloat) -> CGSize {
    .init(width: value, height: 0)
  }
}
