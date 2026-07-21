nonisolated enum TreemapColorNormalization {
    static func normalize<Component: BinaryFloatingPoint>(
        red: inout Component,
        green: inout Component,
        blue: inout Component,
        baseBrightness: Component
    ) {
        let componentSum: Component = red + green + blue
        let factor: Component = componentSum != 0 ? baseBrightness / componentSum : 1
        red *= factor
        green *= factor
        blue *= factor
        distributeOverflow(red: &red, green: &green, blue: &blue)
    }

    static func distributeOverflow<Component: BinaryFloatingPoint>(
        red: inout Component,
        green: inout Component,
        blue: inout Component
    ) {
        if red > 1 {
            distribute(first: &red, second: &green, third: &blue)
        } else if green > 1 {
            distribute(first: &green, second: &red, third: &blue)
        } else if blue > 1 {
            distribute(first: &blue, second: &red, third: &green)
        }
    }

    private static func distribute<Component: BinaryFloatingPoint>(
        first: inout Component,
        second: inout Component,
        third: inout Component
    ) {
        var overflow: Component = (first - 1) / 2
        first = 1
        second += overflow
        third += overflow

        if second > 1 {
            overflow = second - 1
            second = 1
            third += overflow
            assert(third <= 1)
        } else if third > 1 {
            overflow = third - 1
            third = 1
            second += overflow
            assert(second <= 1)
        }
    }
}
