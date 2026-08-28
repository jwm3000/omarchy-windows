#pragma once

#include <algorithm>
#include <optional>
#include <string_view>

namespace AeroSnap {

    struct Point {
        double x = 0;
        double y = 0;
    };

    struct Rect {
        double x = 0;
        double y = 0;
        double w = 0;
        double h = 0;
    };

    enum class Zone {
        None,
        Left,
        Center,
        Right,
        TopLeft,
        TopRight,
        BottomLeft,
        BottomRight,
        Maximize,
    };

    inline int columnsForMonitor(const Rect monitor, const std::string_view configuredColumns) {
        if (configuredColumns == "2")
            return 2;
        if (configuredColumns == "3")
            return 3;

        return monitor.w > 0 && monitor.h > 0 && monitor.w * 9.0 > monitor.h * 16.0 ? 3 : 2;
    }

    inline double outQuart(const double progress) {
        const double remaining = 1.0 - std::clamp(progress, 0.0, 1.0);
        return 1.0 - remaining * remaining * remaining * remaining;
    }

    inline double inCubic(const double progress) {
        const double clamped = std::clamp(progress, 0.0, 1.0);
        return clamped * clamped * clamped;
    }

    inline Rect interpolateRect(const Rect from, const Rect to, const double progress) {
        const double clamped = std::clamp(progress, 0.0, 1.0);
        return {
            from.x + (to.x - from.x) * clamped,
            from.y + (to.y - from.y) * clamped,
            from.w + (to.w - from.w) * clamped,
            from.h + (to.h - from.h) * clamped,
        };
    }

    inline Rect scaleRectFromCenter(const Rect rect, const double scale) {
        const double clamped = std::max(0.0, scale);
        const double width   = rect.w * clamped;
        const double height  = rect.h * clamped;
        return {
            rect.x + (rect.w - width) / 2.0,
            rect.y + (rect.h - height) / 2.0,
            width,
            height,
        };
    }

    inline Zone zoneAt(const Point cursor, const Rect monitor, const double edgeThreshold, const double cornerRatio, const int columns) {
        if (monitor.w <= 0 || monitor.h <= 0 || edgeThreshold < 0)
            return Zone::None;

        const auto ratio          = std::clamp(cornerRatio, 0.0, 0.45);
        const bool nearLeft       = cursor.x <= monitor.x + edgeThreshold;
        const bool nearRight      = cursor.x >= monitor.x + monitor.w - edgeThreshold;
        const bool nearTop        = cursor.y <= monitor.y + edgeThreshold;
        const bool nearBottom     = cursor.y >= monitor.y + monitor.h - edgeThreshold;
        const bool inLeftRegion   = cursor.x <= monitor.x + monitor.w * ratio;
        const bool inRightRegion  = cursor.x >= monitor.x + monitor.w * (1.0 - ratio);
        const bool inTopRegion    = cursor.y <= monitor.y + monitor.h * ratio;
        const bool inBottomRegion = cursor.y >= monitor.y + monitor.h * (1.0 - ratio);

        if ((nearTop && inLeftRegion) || (nearLeft && inTopRegion))
            return Zone::TopLeft;
        if ((nearTop && inRightRegion) || (nearRight && inTopRegion))
            return Zone::TopRight;
        if (nearBottom && columns == 3) {
            if (cursor.x < monitor.x + monitor.w / 3.0)
                return Zone::Left;
            if (cursor.x > monitor.x + monitor.w * 2.0 / 3.0)
                return Zone::Right;
            return Zone::Center;
        }
        if ((nearBottom && inLeftRegion) || (nearLeft && inBottomRegion))
            return Zone::BottomLeft;
        if ((nearBottom && inRightRegion) || (nearRight && inBottomRegion))
            return Zone::BottomRight;
        if (nearTop)
            return Zone::Maximize;
        if (nearLeft)
            return Zone::Left;
        if (nearRight)
            return Zone::Right;

        return Zone::None;
    }

    inline std::optional<Rect> rectForZone(const Rect workArea, const Zone zone, const double horizontalGap, const double verticalGap, const int columns) {
        if (workArea.w <= 0 || workArea.h <= 0 || horizontalGap < 0 || verticalGap < 0)
            return std::nullopt;

        if (zone == Zone::Maximize)
            return workArea;

        const int    columnCount = columns == 3 ? 3 : 2;
        const double columnWidth = (workArea.w - horizontalGap * (columnCount - 1)) / columnCount;
        const double halfWidth   = (workArea.w - horizontalGap) / 2.0;
        const double rowHeight   = (workArea.h - verticalGap) / 2.0;
        if (columnWidth <= 0 || halfWidth <= 0 || rowHeight <= 0)
            return std::nullopt;

        switch (zone) {
            case Zone::Left: return Rect{workArea.x, workArea.y, columnWidth, workArea.h};
            case Zone::Center:
                if (columnCount != 3)
                    return std::nullopt;
                return Rect{workArea.x + columnWidth + horizontalGap, workArea.y, columnWidth, workArea.h};
            case Zone::Right: return Rect{workArea.x + (columnWidth + horizontalGap) * (columnCount - 1), workArea.y, columnWidth, workArea.h};
            case Zone::TopLeft: return Rect{workArea.x, workArea.y, halfWidth, rowHeight};
            case Zone::TopRight: return Rect{workArea.x + halfWidth + horizontalGap, workArea.y, halfWidth, rowHeight};
            case Zone::BottomLeft: return Rect{workArea.x, workArea.y + rowHeight + verticalGap, halfWidth, rowHeight};
            case Zone::BottomRight: return Rect{workArea.x + halfWidth + horizontalGap, workArea.y + rowHeight + verticalGap, halfWidth, rowHeight};
            case Zone::None:
            case Zone::Maximize: return std::nullopt;
        }

        return std::nullopt;
    }

} // namespace AeroSnap
