//
//  Saturation.swift
//  Colorful
//
//  Created by wong on 4/20/25.
//


import SwiftUI

class UnevenRoundedModel: ObservableObject {
    @Published var topLeadingRadius: CGFloat = 8
    @Published var topTrailingRadius: CGFloat = 8
    @Published var bottomLeadingRadius: CGFloat = 0
    @Published var bottomTrailingRadius: CGFloat = 0
    init(
        topLeadingRadius: CGFloat = 8,
        topTrailingRadius: CGFloat = 8,
        bottomLeadingRadius: CGFloat = 0,
        bottomTrailingRadius: CGFloat = 0
    ) {
        self.topLeadingRadius = topLeadingRadius
        self.topTrailingRadius = topTrailingRadius
        self.bottomLeadingRadius = bottomLeadingRadius
        self.bottomTrailingRadius = bottomTrailingRadius
    }
}

public struct Saturation: View {
    @ObservedObject var viewModel: AlphaSliderModel = .init()
    @ObservedObject var rounded: UnevenRoundedModel = .init()
    @Binding var saturation: CGFloat // 饱和度 (0.0 到 1.0)
    @Binding var brightness: CGFloat // 亮度 (0.0 到 1.0)
    var hue: CGFloat // 固定的色相 (0.0 到 1.0)
    /// LOCAL: all four corners, set by the caller. Upstream fixes the top two at
    /// 8 and squares the bottom two, because it only ever stacks this above a
    /// hue slider; standing on its own it needs to be a rounded box.
    var cornerRadius: CGFloat
    public init(
        saturation: Binding<CGFloat>,
        brightness: Binding<CGFloat>,
        hue: CGFloat = 0,
        cornerRadius: CGFloat = 8
    ) {
        self._saturation = saturation
        self._brightness = brightness
        self.hue = hue
        self.cornerRadius = cornerRadius
        self.rounded = UnevenRoundedModel(topLeadingRadius: cornerRadius,
                                          topTrailingRadius: cornerRadius,
                                          bottomLeadingRadius: cornerRadius,
                                          bottomTrailingRadius: cornerRadius)
    }
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                UnevenRoundedRectangle(
                    topLeadingRadius: rounded.topLeadingRadius,
                    bottomLeadingRadius: rounded.bottomLeadingRadius,
                    bottomTrailingRadius: rounded.bottomTrailingRadius,
                    topTrailingRadius: rounded.topTrailingRadius
                )
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(hue: hue, saturation: 0, brightness: 1),
                            Color(hue: hue, saturation: 1, brightness: 1)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white, location: 0.0), // 顶部：白色
                            .init(color: Color(white: 0.6, opacity: 0.5), location: 0.4), // 中间：半透明灰色
                            .init(color: Color(white: 0.05), location: 1.0) // 底部：浅灰色
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .blendMode(.multiply)
                    .mask(
                        UnevenRoundedRectangle(
                            topLeadingRadius: rounded.topLeadingRadius,
                            bottomLeadingRadius: rounded.bottomLeadingRadius,
                            bottomTrailingRadius: rounded.bottomTrailingRadius,
                            topTrailingRadius: rounded.topTrailingRadius
                        )
                    )
                )
                
                // 显示当前选择的颜色指示器
                Circle()
                    .fill(Color(hue: hue, saturation: saturation, brightness: brightness))
                    .frame(width: viewModel.pointSize.width, height: viewModel.pointSize.height)
                    .overlay(Circle().stroke(Color.secondary.opacity(0.37), lineWidth: 2))
                    .overlay(Circle().stroke(Color.white, lineWidth: 1))
                    // LOCAL: kept inside the frame by half its own width.
                    // Upstream centres it on the true position, so at any edge
                    // half the indicator falls outside — which either overlaps
                    // whatever is next in the stack or, clipped, leaves a
                    // half-circle that reads as a drawing fault. The cost is
                    // that the indicator sits up to 7pt in from the edge when
                    // the value is hard against it.
                    .position(
                        x: clamp(saturation * geometry.size.width,
                                 within: geometry.size.width),
                        y: clamp((1 - brightness) * geometry.size.height,
                                 within: geometry.size.height)
                    )
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // 将触摸位置映射到饱和度和亮度
                        let x = value.location.x
                        let y = value.location.y
                        let width = geometry.size.width
                        let height = geometry.size.height

                        // 限制范围并计算饱和度和亮度
                        saturation = min(max(x / width, 0), 1)
                        brightness = 1 - min(max(y / height, 0), 1) // 亮度从上到下递减
                    }
            )
        }
        //.aspectRatio(1, contentMode: .fit) // 保持正方形
    }

    private func clamp(_ v: CGFloat, within extent: CGFloat) -> CGFloat {
        let r = viewModel.pointSize.width / 2
        return min(max(v, r), max(extent - r, r))
    }
}

#Preview {
    @Previewable @State var saturation: CGFloat = 1.0
    @Previewable @State var brightness: CGFloat = 1.0
    @Previewable @State var hue: CGFloat = 0.0
    Saturation(
        saturation: $saturation,
        brightness: $brightness,
        hue: hue
    )
    .frame(width: 200, height: 200)
    .padding(.top)
    Saturation(
        saturation: $saturation,
        brightness: $brightness,
        hue: hue
    )
    .frame(width: 200, height: 120)
    .padding()
}
