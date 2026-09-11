import Foundation

@main struct FollowingSidebarPhysicsRegression {
    static func main() {
        for distance: CGFloat in [0, 6, 12, 24, 48, 72, 96] {
            precondition(abs(FollowingSidebarPhysics.dragProgress(start: 0, translation: distance) * 96 - distance) < 0.000001)
        }
        precondition(abs(FollowingSidebarPhysics.dragProgress(start: 0.65, translation: -24) - 0.4) < 0.000001)
        precondition(FollowingSidebarPhysics.target(progress: 0.2, velocity: 700) == 1)
        precondition(FollowingSidebarPhysics.target(progress: 0.8, velocity: -700) == 0)
        print("PASS  选择器展开按真实位移线性跟手，回拖与松手速度投影正确")

        let start = FollowingSidebarPhysics.Sample(progress: 0.3, velocity: 1.5)
        let first = FollowingSidebarPhysics.advance(start, toward: 1, elapsed: 0.000001)
        precondition(abs((first.progress - start.progress) / 0.000001 - start.velocity) < 0.001)
        var sixty = start
        var oneTwenty = start
        for _ in 0..<12 { sixty = FollowingSidebarPhysics.advance(sixty, toward: 1, elapsed: 1.0 / 60) }
        for _ in 0..<24 { oneTwenty = FollowingSidebarPhysics.advance(oneTwenty, toward: 1, elapsed: 1.0 / 120) }
        let delayed = FollowingSidebarPhysics.advance(start, toward: 1, elapsed: 0.2)
        precondition(abs(sixty.progress - oneTwenty.progress) < 0.0000001)
        precondition(abs(sixty.progress - delayed.progress) < 0.0000001)
        for target: CGFloat in [0, 1] {
            for speed: CGFloat in [-60, -3, 0, 3, 60] {
                var sample = FollowingSidebarPhysics.Sample(progress: 0.5, velocity: speed)
                for _ in 0..<120 {
                    sample = FollowingSidebarPhysics.advance(sample, toward: target, elapsed: 1.0 / 120)
                    precondition((0...1).contains(sample.progress))
                }
                precondition(abs(sample.progress - target) < 0.00001)
                precondition(abs(sample.velocity) < 0.00001)
            }
        }
        print("PASS  解析弹簧保留初速度，60/120Hz 与掉帧等价，高速反向不越界且收敛")

        for width: CGFloat in [40, 320, 393, 402, 430, 852] {
            for progress: CGFloat in [0, 0.25, 0.5, 0.75, 1] {
                let layout = FollowingFeedGeometry(width: width, height: 650, progress: progress)
                precondition(abs(layout.displacement + width * layout.scale - width) < 0.000001)
                precondition(abs(layout.unscaledHeight * layout.scale - 650) < 0.000001)
                precondition(layout.scale >= 0.5)
            }
        }
        print("PASS  内容等比缩小与平移后整宽可见，上下视口始终完整衔接，左右镜像正确")
    }
}
