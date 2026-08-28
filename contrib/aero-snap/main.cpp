#define WLR_USE_UNSTABLE

#include "geometry.hpp"

#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/config/ConfigManager.hpp>
#include <hyprland/src/config/shared/complex/ComplexDataTypes.hpp>
#include <hyprland/src/config/values/types/BoolValue.hpp>
#include <hyprland/src/config/values/types/ColorValue.hpp>
#include <hyprland/src/config/values/types/FloatValue.hpp>
#include <hyprland/src/config/values/types/IntValue.hpp>
#include <hyprland/src/config/values/types/StringValue.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/layout/space/Space.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/pass/RectPassElement.hpp>
#include <hyprland/src/state/MonitorState.hpp>

#include <linux/input-event-codes.h>
#include <unistd.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <optional>
#include <string>
#include <vector>

namespace {

    using AeroSnap::Zone;

    using PreviewClock = std::chrono::steady_clock;

    HANDLE pluginHandle = nullptr;

    struct SConfigValues {
        SP<Config::Values::CBoolValue>   enabled;
        SP<Config::Values::CBoolValue>   floatingModeOnly;
        SP<Config::Values::CStringValue> columns;
        SP<Config::Values::CIntValue>    edgeThreshold;
        SP<Config::Values::CFloatValue>  cornerRatio;
        SP<Config::Values::CColorValue>  previewColor;
        SP<Config::Values::CColorValue>  previewBorderColor;
        SP<Config::Values::CIntValue>    previewBorderSize;
        SP<Config::Values::CIntValue>    previewRounding;
        SP<Config::Values::CBoolValue>   previewBlur;
        SP<Config::Values::CIntValue>    previewAnimationDuration;
    };

    struct SPlacement {
        SP<Layout::ITarget> target;
        Zone                zone = Zone::None;
        CBox                previewBox;
        CBox                clientBox;
    };

    struct SPreview {
        PHLMONITORREF             monitor;
        CBox                      fromBox;
        CBox                      targetBox;
        PreviewClock::time_point  startedAt;
        std::chrono::milliseconds duration{0};
        float                     fromOpacity   = 0.F;
        float                     targetOpacity = 1.F;
    };

    struct SPreviewFrame {
        CBox  box;
        float opacity = 0.F;
        bool  settled = true;
    };

    struct SSnapRecord {
        PHLWINDOWREF window;
        CBox         restoreBox;
        CBox         snappedBox;
        Zone         zone = Zone::None;
    };

    struct SDragState {
        SP<Layout::ITarget>       target;
        CBox                      startBox;
        std::optional<SPlacement> candidate;
        bool                      modeActive = false;
    };

    struct SPluginState {
        SConfigValues             config;
        std::string               enabledMarker;
        std::optional<SPreview>   preview;
        std::optional<SDragState> drag;
        std::vector<SSnapRecord>  records;
        UP<SEventLoopDoLaterLock> pendingApply;
        CHyprSignalListener       mouseMoveListener;
        CHyprSignalListener       mouseButtonListener;
        CHyprSignalListener       renderListener;
        CHyprSignalListener       windowDestroyListener;
        CHyprSignalListener       windowFloatingListener;
    };

    UP<SPluginState> state;

    AeroSnap::Rect   toRect(const CBox& box) {
        return {box.x, box.y, box.w, box.h};
    }

    CBox toBox(const AeroSnap::Rect rect) {
        CBox box{rect.x, rect.y, rect.w, rect.h};
        box.round();
        return box;
    }

    bool sameBox(const CBox& lhs, const CBox& rhs) {
        return lhs.x == rhs.x && lhs.y == rhs.y && lhs.w == rhs.w && lhs.h == rhs.h;
    }

    void damagePreviewBox(const CBox& box) {
        constexpr double padding = 12;
        g_pHyprRenderer->damageBox({box.x - padding, box.y - padding, box.w + padding * 2, box.h + padding * 2});
    }

    SPreviewFrame previewFrame(const SPreview& preview, const PreviewClock::time_point now) {
        const double elapsed  = std::chrono::duration<double, std::milli>(now - preview.startedAt).count();
        const double duration = static_cast<double>(preview.duration.count());
        const double progress = duration <= 0.0 ? 1.0 : std::clamp(elapsed / duration, 0.0, 1.0);
        const double eased    = preview.targetOpacity < preview.fromOpacity ? AeroSnap::inCubic(progress) : AeroSnap::outQuart(progress);

        return {
            toBox(AeroSnap::interpolateRect(toRect(preview.fromBox), toRect(preview.targetBox), eased)),
            static_cast<float>(preview.fromOpacity + (preview.targetOpacity - preview.fromOpacity) * eased),
            progress >= 1.0,
        };
    }

    std::chrono::milliseconds previewDuration(const CBox& fromBox, const CBox& targetBox, const PHLMONITOR& monitor, const double opacityDistance = 0.0) {
        const int configured = std::max(0, static_cast<int>(state->config.previewAnimationDuration->value()));
        if (configured == 0 || !monitor)
            return std::chrono::milliseconds{0};

        const CBox   monitorBox  = monitor->logicalBox();
        const double reference   = std::max(1.0, monitorBox.w / 3.0);
        const double boxDistance = std::max({
            std::abs(targetBox.x - fromBox.x),
            std::abs(targetBox.y - fromBox.y),
            std::abs(targetBox.w - fromBox.w),
            std::abs(targetBox.h - fromBox.h),
        });
        const double distance    = std::clamp(std::max(boxDistance / reference, opacityDistance), 0.1, 1.0);
        return std::chrono::milliseconds{std::max(1, static_cast<int>(std::round(configured * distance)))};
    }

    void clearPreview() {
        if (!state || !state->preview)
            return;

        if (state->preview->targetOpacity <= 0.F)
            return;

        const auto now        = PreviewClock::now();
        const auto current    = previewFrame(*state->preview, now);
        const CBox target     = toBox(AeroSnap::scaleRectFromCenter(toRect(current.box), 0.985));
        const auto monitor    = state->preview->monitor.lock();
        const int  configured = std::max(0, static_cast<int>(state->config.previewAnimationDuration->value()));
        const auto duration =
            configured == 0 ? std::chrono::milliseconds{0} : std::chrono::milliseconds{std::max(1, static_cast<int>(std::round(configured * 0.625 * current.opacity)))};

        damagePreviewBox(current.box);
        damagePreviewBox(target);
        state->preview = SPreview{monitor, current.box, target, now, duration, current.opacity, 0.F};
    }

    void setPreview(const PHLMONITOR& monitor, const CBox& box) {
        if (state->preview && state->preview->monitor.lock() == monitor && sameBox(state->preview->targetBox, box) && state->preview->targetOpacity >= 1.F)
            return;

        const auto now = PreviewClock::now();
        if (state->preview && state->preview->monitor.lock() == monitor) {
            const auto current  = previewFrame(*state->preview, now);
            const auto duration = previewDuration(current.box, box, monitor, 1.0 - current.opacity);
            damagePreviewBox(current.box);
            damagePreviewBox(box);
            state->preview = SPreview{monitor, current.box, box, now, duration, current.opacity, 1.F};
            return;
        }

        if (state->preview) {
            const auto current = previewFrame(*state->preview, now);
            damagePreviewBox(current.box);
            damagePreviewBox(state->preview->targetBox);
        }

        const CBox from       = toBox(AeroSnap::scaleRectFromCenter(toRect(box), 0.96));
        const int  configured = std::max(0, static_cast<int>(state->config.previewAnimationDuration->value()));
        state->preview        = SPreview{monitor, from, box, now, std::chrono::milliseconds{configured}, 0.F, 1.F};
        damagePreviewBox(from);
        damagePreviewBox(box);
    }

    void pruneRecords() {
        std::erase_if(state->records, [](const auto& record) { return !record.window.valid() || record.window.expired(); });
    }

    SSnapRecord* recordFor(const PHLWINDOW& window) {
        pruneRecords();
        const auto found = std::ranges::find_if(state->records, [&](const auto& record) { return record.window.lock() == window; });
        return found == state->records.end() ? nullptr : &*found;
    }

    void rememberSnap(const PHLWINDOW& window, const CBox& restoreBox, const CBox& snappedBox, const Zone zone) {
        if (const auto record = recordFor(window)) {
            record->snappedBox = snappedBox;
            record->zone       = zone;
            return;
        }

        state->records.push_back({window, restoreBox, snappedBox, zone});
    }

    void forgetRestoreBox(const PHLWINDOW& window) {
        std::erase_if(state->records, [&](const auto& record) { return record.window.lock() == window; });
    }

    void restoreTrackedWindows() {
        auto records = std::move(state->records);
        state->records.clear();

        for (const auto& record : records) {
            const auto window = record.window.lock();
            if (!Desktop::View::validMapped(window) || !window->m_target || !window->m_target->floating())
                continue;

            const auto target = window->m_target;
            if (record.zone == Zone::Maximize) {
                if (!Fullscreen::controller()->isFullscreen(window, Fullscreen::FSMODE_MAXIMIZED))
                    continue;
                Fullscreen::controller()->setFullscreenMode(window, Fullscreen::FSMODE_NONE);
            } else if (!sameBox(target->position(), record.snappedBox))
                continue;

            g_layoutManager->setTargetGeom(record.restoreBox, target);
            target->warpPositionSize();
            target->damageEntire();
        }
    }

    SSnapRecord* currentSnapRecord(const SP<Layout::ITarget>& target, const bool allowMoved) {
        if (!target || !Desktop::View::validMapped(target->window()))
            return nullptr;

        const auto window = target->window();
        const auto record = recordFor(window);
        if (!record)
            return nullptr;

        bool matches = false;
        if (record->zone == Zone::Maximize) {
            matches = Fullscreen::controller()->isFullscreen(window, Fullscreen::FSMODE_MAXIMIZED);
        } else {
            const CBox current = target->position();
            matches            = current.w == record->snappedBox.w && current.h == record->snappedBox.h;
            if (matches && !allowMoved)
                matches = current.x == record->snappedBox.x && current.y == record->snappedBox.y;
        }

        if (matches)
            return record;

        forgetRestoreBox(window);
        return nullptr;
    }

    bool floatingModeActive() {
        if (!state || !state->config.enabled->value())
            return false;
        if (!state->config.floatingModeOnly->value())
            return true;

        return access(state->enabledMarker.c_str(), F_OK) == 0;
    }

    PHLWORKSPACE activeWorkspace(const PHLMONITOR& monitor) {
        return monitor->m_activeSpecialWorkspace ? monitor->m_activeSpecialWorkspace : monitor->m_activeWorkspace;
    }

    std::optional<SPlacement> placementFor(const SP<Layout::ITarget>& target, const PHLMONITOR& monitor, const Zone zone) {
        if (!target || !target->floating() || !Desktop::View::validMapped(target->window()) || !monitor || zone == Zone::None)
            return std::nullopt;

        const auto workspace = activeWorkspace(monitor);
        if (!workspace || !workspace->m_space)
            return std::nullopt;

        const CBox   workArea          = workspace->m_space->workArea(zone == Zone::Maximize);
        const auto   configuredColumns = state->config.columns->value();
        const int    columns           = AeroSnap::columnsForMonitor(toRect(monitor->logicalBox()), configuredColumns);

        static auto  gapsInValue   = CConfigValue<Config::IComplexConfigValue>("general:gaps_in");
        const auto*  gapsIn        = sc<Config::CCssGapData*>(gapsInValue.ptr());
        const double horizontalGap = gapsIn->m_left + gapsIn->m_right;
        const double verticalGap   = gapsIn->m_top + gapsIn->m_bottom;
        const auto   zoneRect      = AeroSnap::rectForZone(toRect(workArea), zone, horizontalGap, verticalGap, columns);
        if (!zoneRect)
            return std::nullopt;

        const CBox requestedOuter = toBox(*zoneRect);
        if (zone == Zone::Maximize)
            return SPlacement{target, zone, requestedOuter, {}};

        const auto     window  = target->window();
        const auto     extents = window->getWindowExtentsUnified(Desktop::View::RESERVED_EXTENTS | Desktop::View::INPUT_EXTENTS);
        const Vector2D availableSize{
            requestedOuter.w - extents.topLeft.x - extents.bottomRight.x,
            requestedOuter.h - extents.topLeft.y - extents.bottomRight.y,
        };
        const Vector2D minSize         = target->minSize().value_or(Vector2D{1, 1});
        const Vector2D reportedMaxSize = target->maxSize().value_or(Math::VECTOR2D_MAX);
        const Vector2D maxSize{
            std::max(minSize.x, reportedMaxSize.x),
            std::max(minSize.y, reportedMaxSize.y),
        };

        if (availableSize.x < minSize.x || availableSize.y < minSize.y)
            return std::nullopt;

        const Vector2D clientSize{
            std::clamp(availableSize.x, minSize.x, maxSize.x),
            std::clamp(availableSize.y, minSize.y, maxSize.y),
        };
        const Vector2D actualOuterSize{
            clientSize.x + extents.topLeft.x + extents.bottomRight.x,
            clientSize.y + extents.topLeft.y + extents.bottomRight.y,
        };
        CBox actualOuter{
            requestedOuter.x + (requestedOuter.w - actualOuterSize.x) / 2.0,
            requestedOuter.y + (requestedOuter.h - actualOuterSize.y) / 2.0,
            actualOuterSize.x,
            actualOuterSize.y,
        };
        CBox clientBox{
            actualOuter.x + extents.topLeft.x,
            actualOuter.y + extents.topLeft.y,
            clientSize.x,
            clientSize.y,
        };
        actualOuter.round();
        clientBox.round();

        return SPlacement{target, zone, actualOuter, clientBox};
    }

    void applyPlacement(const SPlacement& placement, const CBox& restoreBox) {
        const auto target = placement.target;
        if (!target || !target->floating() || !Desktop::View::validMapped(target->window()))
            return;

        const auto window = target->window();

        if (placement.zone == Zone::Maximize) {
            Fullscreen::controller()->setFullscreenMode(window, Fullscreen::FSMODE_MAXIMIZED);
            rememberSnap(window, restoreBox, placement.previewBox, placement.zone);
            return;
        }

        if (Fullscreen::controller()->isFullscreen(window))
            Fullscreen::controller()->setFullscreenMode(window, Fullscreen::FSMODE_NONE);

        g_layoutManager->setTargetGeom(placement.clientBox, target);
        target->warpPositionSize();
        target->damageEntire();
        rememberSnap(window, restoreBox, placement.clientBox, placement.zone);
    }

    bool restoreSnappedDrag(const SP<Layout::ITarget>& target, const Vector2D cursor, Event::SCallbackInfo& info) {
        const auto window = target->window();
        const auto record = currentSnapRecord(target, true);
        if (!record)
            return false;

        const CBox restoreBox = record->restoreBox;
        const auto extents    = window->getWindowExtentsUnified(Desktop::View::RESERVED_EXTENTS | Desktop::View::INPUT_EXTENTS);
        const CBox current    = target->position();
        const CBox currentOuter{
            current.x - extents.topLeft.x,
            current.y - extents.topLeft.y,
            current.w + extents.topLeft.x + extents.bottomRight.x,
            current.h + extents.topLeft.y + extents.bottomRight.y,
        };
        const double   anchorX = std::clamp((cursor.x - currentOuter.x) / std::max(1.0, currentOuter.w), 0.08, 0.92);
        const double   anchorY = std::clamp(cursor.y - currentOuter.y, 0.0, std::max(0.0, currentOuter.h * 0.25));
        const Vector2D restoredOuterSize{
            restoreBox.w + extents.topLeft.x + extents.bottomRight.x,
            restoreBox.h + extents.topLeft.y + extents.bottomRight.y,
        };
        CBox anchoredRestore{
            cursor.x - restoredOuterSize.x * anchorX + extents.topLeft.x,
            cursor.y - anchorY + extents.topLeft.y,
            restoreBox.w,
            restoreBox.h,
        };
        anchoredRestore.round();

        if (Fullscreen::controller()->isFullscreen(window))
            Fullscreen::controller()->setFullscreenMode(window, Fullscreen::FSMODE_NONE);
        forgetRestoreBox(window);
        clearPreview();
        g_layoutManager->endDragTarget();
        g_layoutManager->setTargetGeom(anchoredRestore, target);
        target->warpPositionSize();
        g_layoutManager->beginDragTarget(target, MBIND_MOVE);
        state->drag    = SDragState{target, anchoredRestore, std::nullopt, true};
        info.cancelled = true;
        return true;
    }

    void resetDrag() {
        clearPreview();
        state->drag.reset();
    }

    void onMouseMove(const Vector2D cursor, Event::SCallbackInfo& info) {
        if (!state)
            return;

        const auto& controller = g_layoutManager->dragController();
        const auto  target     = controller->target();
        if (target && controller->mode() != MBIND_MOVE && controller->dragThresholdReached() && Desktop::View::validMapped(target->window()))
            forgetRestoreBox(target->window());
        if (!target || controller->mode() != MBIND_MOVE || controller->draggingTiled() || !target->floating() || !Desktop::View::validMapped(target->window())) {
            resetDrag();
            return;
        }
        if (!state->drag || state->drag->target != target)
            state->drag = SDragState{target, target->position(), std::nullopt, floatingModeActive()};

        if (!state->drag->modeActive)
            return;

        if (!controller->dragThresholdReached())
            currentSnapRecord(target, false);

        if (controller->dragThresholdReached() && restoreSnappedDrag(target, cursor, info))
            return;

        if (!controller->dragThresholdReached()) {
            clearPreview();
            state->drag->candidate.reset();
            return;
        }

        const auto monitor = State::monitorState()->query().vec(cursor).run();
        if (!monitor) {
            clearPreview();
            state->drag->candidate.reset();
            return;
        }

        const auto monitorBox        = monitor->logicalBox();
        const auto configuredColumns = state->config.columns->value();
        const int  columns           = AeroSnap::columnsForMonitor(toRect(monitorBox), configuredColumns);
        const auto zone      = AeroSnap::zoneAt({cursor.x, cursor.y}, toRect(monitorBox), state->config.edgeThreshold->value(), state->config.cornerRatio->value(), columns);
        const auto placement = placementFor(target, monitor, zone);
        if (!placement) {
            clearPreview();
            state->drag->candidate.reset();
            return;
        }

        state->drag->candidate = placement;
        setPreview(monitor, placement->previewBox);
    }

    void onMouseButton(const IPointer::SButtonEvent event) {
        if (!state || event.state != WL_POINTER_BUTTON_STATE_RELEASED || event.button != BTN_LEFT || !state->drag)
            return;

        const auto drag = *state->drag;
        resetDrag();
        if (!drag.candidate)
            return;

        const auto placement = *drag.candidate;
        state->pendingApply  = g_pEventLoopManager->doLaterLock([placement, restoreBox = drag.startBox] {
            if (!state || !floatingModeActive() || !placement.target || !Desktop::View::validMapped(placement.target->window()))
                return;

            if (g_layoutManager->dragController()->target() == placement.target)
                g_layoutManager->endDragTarget();
            applyPlacement(placement, restoreBox);
        });
    }

    void onRenderStage(const eRenderStage stageValue) {
        if (!state || stageValue != RENDER_POST_WINDOWS || !state->preview)
            return;

        const auto monitor = g_pHyprRenderer->renderData().pMonitor.lock();
        if (!monitor || state->preview->monitor.lock() != monitor)
            return;

        const auto frame = previewFrame(*state->preview, PreviewClock::now());
        if (frame.settled && state->preview->targetOpacity <= 0.F) {
            damagePreviewBox(frame.box);
            state->preview.reset();
            return;
        }

        if (!frame.settled) {
            damagePreviewBox(frame.box);
            damagePreviewBox(state->preview->targetBox);
        }

        CBox outer = frame.box;
        outer.translate(-monitor->m_position).scale(monitor->m_scale).round();

        const float opacity  = std::clamp(frame.opacity, 0.F, 1.F);
        const int   border   = std::max(0, static_cast<int>(std::round(state->config.previewBorderSize->value() * monitor->m_scale)));
        const int   rounding = std::max(0, static_cast<int>(std::round(state->config.previewRounding->value() * monitor->m_scale)));
        if (border > 0) {
            const CHyprColor            borderColor{static_cast<uint64_t>(state->config.previewBorderColor->value())};
            CRectPassElement::SRectData borderData;
            borderData.box   = outer;
            borderData.color = borderColor.modifyA(static_cast<float>(borderColor.a) * opacity);
            borderData.round = rounding;
            g_pHyprRenderer->m_renderPass.add(makeUnique<CRectPassElement>(borderData));
        }

        CBox inner{outer.x + border, outer.y + border, outer.w - border * 2, outer.h - border * 2};
        if (inner.w <= 0 || inner.h <= 0)
            return;

        const CHyprColor            fillColor{static_cast<uint64_t>(state->config.previewColor->value())};
        CRectPassElement::SRectData fillData;
        fillData.box   = inner;
        fillData.color = fillColor.modifyA(static_cast<float>(fillColor.a) * opacity);
        fillData.round = std::max(0, rounding - border);
        fillData.blur  = state->config.previewBlur->value();
        fillData.blurA = 0.48F * opacity;
        g_pHyprRenderer->m_renderPass.add(makeUnique<CRectPassElement>(fillData));
    }

} // namespace

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    pluginHandle = handle;

    const std::string runningHash = __hyprland_api_get_hash();
    const std::string headersHash = __hyprland_api_get_client_hash();
    if (runningHash != headersHash) {
        HyprlandAPI::addNotification(pluginHandle, "[omarchy-windows-snap] Hyprland version mismatch", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("omarchy-windows-snap was built for a different Hyprland version");
    }

    state                        = makeUnique<SPluginState>();
    const auto* runtimeDirectory = std::getenv("XDG_RUNTIME_DIR");
    state->enabledMarker         = runtimeDirectory && *runtimeDirectory ? std::string{runtimeDirectory} + "/omarchy-floating-mode/enabled" :
                                                                           "/run/user/" + std::to_string(getuid()) + "/omarchy-floating-mode/enabled";

    state->config.enabled = makeShared<Config::Values::CBoolValue>("plugin:omarchy_windows_snap:enabled", "Enable Aero-style drag snap zones", true);
    state->config.floatingModeOnly =
        makeShared<Config::Values::CBoolValue>("plugin:omarchy_windows_snap:floating_mode_only", "Activate only while Omarchy Floating Mode is on", true);
    state->config.columns =
        makeShared<Config::Values::CStringValue>("plugin:omarchy_windows_snap:columns", "Full-height snap columns: auto, 2, or 3", "auto",
                                                 Config::Values::SStringValueOptions{.validator = [](const Config::STRING& value) -> std::expected<void, std::string> {
                                                     if (value == "auto" || value == "2" || value == "3")
                                                         return {};
                                                     return std::unexpected("expected auto, 2, or 3");
                                                 }});
    state->config.edgeThreshold = makeShared<Config::Values::CIntValue>("plugin:omarchy_windows_snap:edge_threshold", "Logical pixels from a monitor edge that activate a zone", 12,
                                                                        Config::Values::SIntValueOptions{.min = 1, .max = 128});
    state->config.cornerRatio   = makeShared<Config::Values::CFloatValue>("plugin:omarchy_windows_snap:corner_ratio", "Fraction of each monitor edge reserved for corner zones",
                                                                          0.25F, Config::Values::SFloatValueOptions{.min = 0.05F, .max = 0.45F});
    state->config.previewColor  = makeShared<Config::Values::CColorValue>("plugin:omarchy_windows_snap:preview_color", "Snap preview fill color", 0x331e3a8a);
    state->config.previewBorderColor       = makeShared<Config::Values::CColorValue>("plugin:omarchy_windows_snap:preview_border_color", "Snap preview border color", 0xbd1d4ed8);
    state->config.previewBorderSize        = makeShared<Config::Values::CIntValue>("plugin:omarchy_windows_snap:preview_border_size", "Snap preview border size", 2,
                                                                                   Config::Values::SIntValueOptions{.min = 0, .max = 16});
    state->config.previewRounding          = makeShared<Config::Values::CIntValue>("plugin:omarchy_windows_snap:preview_rounding", "Snap preview corner radius", 8,
                                                                                   Config::Values::SIntValueOptions{.min = 0, .max = 64});
    state->config.previewBlur              = makeShared<Config::Values::CBoolValue>("plugin:omarchy_windows_snap:preview_blur", "Blur behind the snap preview", true);
    state->config.previewAnimationDuration = makeShared<Config::Values::CIntValue>(
        "plugin:omarchy_windows_snap:preview_animation_duration", "Snap preview animation duration in milliseconds", 200, Config::Values::SIntValueOptions{.min = 0, .max = 1000});

    HyprlandAPI::addConfigValueV2(pluginHandle, state->config.enabled);
    HyprlandAPI::addConfigValueV2(pluginHandle, state->config.floatingModeOnly);
    HyprlandAPI::addConfigValueV2(pluginHandle, state->config.columns);
    HyprlandAPI::addConfigValueV2(pluginHandle, state->config.edgeThreshold);
    HyprlandAPI::addConfigValueV2(pluginHandle, state->config.cornerRatio);
    HyprlandAPI::addConfigValueV2(pluginHandle, state->config.previewColor);
    HyprlandAPI::addConfigValueV2(pluginHandle, state->config.previewBorderColor);
    HyprlandAPI::addConfigValueV2(pluginHandle, state->config.previewBorderSize);
    HyprlandAPI::addConfigValueV2(pluginHandle, state->config.previewRounding);
    HyprlandAPI::addConfigValueV2(pluginHandle, state->config.previewBlur);
    HyprlandAPI::addConfigValueV2(pluginHandle, state->config.previewAnimationDuration);

    state->mouseMoveListener      = Event::bus()->m_events.input.mouse.move.listen([](Vector2D cursor, Event::SCallbackInfo& info) { onMouseMove(cursor, info); });
    state->mouseButtonListener    = Event::bus()->m_events.input.mouse.button.listen([](IPointer::SButtonEvent event, Event::SCallbackInfo&) { onMouseButton(event); });
    state->renderListener         = Event::bus()->m_events.render.stage.listen([](eRenderStage stageValue) { onRenderStage(stageValue); });
    state->windowDestroyListener  = Event::bus()->m_events.window.destroy.listen([](PHLWINDOWREF window) {
        if (!state)
            return;
        std::erase_if(state->records, [&](const auto& record) { return record.window == window; });
        if (state->drag && state->drag->target && state->drag->target->window() == window.lock())
            resetDrag();
    });
    state->windowFloatingListener = Event::bus()->m_events.window.floating.listen([](PHLWINDOW window) {
        if (state && Desktop::View::validMapped(window) && window->m_target && !window->m_target->floating())
            forgetRestoreBox(window);
    });

    HyprlandAPI::reloadConfig();
    return {"omarchy-windows-snap", "Aero-style drag snap zones for Omarchy Floating Mode", "Norbert Winter and contributors", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    if (!state)
        return;

    clearPreview();
    state->pendingApply.reset();
    restoreTrackedWindows();
    state->mouseMoveListener.reset();
    state->mouseButtonListener.reset();
    state->renderListener.reset();
    state->windowDestroyListener.reset();
    state->windowFloatingListener.reset();
    state.reset();
}
