// geomwars - Geometry Wars: Retro Evolved (Xbox 360), ReXGlue application.
//
// Vulkan is the only render API: the SDK this links is built with REXGLUE_USE_D3D12=OFF
// (tools/setup.ps1), and the Xenos renderer plugin is loaded asking for its Vulkan backend by
// name, so a D3D12 plugin dropped beside the program can't be picked up by mistake.

#pragma once

#include <filesystem>
#include <memory>
#include <string>

#include <rex/cvar.h>
#include <rex/input/device_assignment.h>
#include <rex/input/input_system.h>
#include <rex/logging.h>
#include <rex/rex_app.h>
#include <rex/runtime.h>
#include <rex/system/gpu_plugin.h>
#include <rex/ui/imgui_dialog.h>
#include <rex/ui/keybinds.h>
#include <rex/ui/window.h>

#include "audio_dump.h"
#include "autopilot.h"
#include "crash_report.h"
#include "ui_pad.h"
#include "ui_style.h"

void GeomWarsRaiseTimerResolution();  // timer_resolution.cpp
void GeomWarsRequestRenderDocCapture();  // frame_timing.cpp

// The runtime signs in only player 1 and gives controllers player slots in connection order. A
// virtual XInput device (Logitech's, Steam Input's) can take slot 0 and leave the real pad as an
// unsigned player 2, so by default every controller and the keyboard drive player 1.
REXCVAR_DEFINE_BOOL(geomwars_shared_controllers, true, "GEOMWARS",
                    "Every connected controller (and the keyboard) drives player 1, the "
                    "signed-in profile; off = one controller per player slot")
    .lifecycle(rex::cvar::Lifecycle::kInitOnly);

class GeomWarsApp : public rex::ReXApp {
 public:
  using rex::ReXApp::ReXApp;

  static std::unique_ptr<rex::ui::WindowedApp> Create(rex::ui::WindowedAppContext& ctx) {
    return std::unique_ptr<GeomWarsApp>(new GeomWarsApp(ctx, "geomwars", PPCImageConfig));
  }

 protected:
  // A packaged copy (game\ = the disc's files, user\ = profile and saves beside the program)
  // runs without command-line paths.
  void OnConfigurePaths(rex::PathConfig& paths) override {
    std::error_code error;
    const auto own_dir = std::filesystem::current_path(error);
    if (paths.game_data_root.empty() && std::filesystem::is_directory(own_dir / "game", error)) {
      paths.game_data_root = own_dir / "game";
    }
    if (REXCVAR_GET(user_data_root).empty() &&
        std::filesystem::is_directory(own_dir / "user", error)) {
      paths.user_data_root = own_dir / "user";
      paths.cache_root = own_dir / "user" / "cache";
    }
  }

  void OnPreSetup(rex::RuntimeConfig& config) override {
    GeomWarsRaiseTimerResolution();
    geomwars::crash_report::InstallCrashReporter();

    // Without a GPU plugin the runtime ignores every Vd* call and the game never draws. Load
    // the Xenos plugin's Vulkan backend ourselves; ReXApp would ask for "any".
    if (config.gpu_plugin.empty()) config.gpu_plugin = "xenos";
    if (!config.graphics) {
      config.graphics = rex::system::LoadGpuPlugin(config.gpu_plugin, "vulkan");
      if (config.graphics) {
        REXLOG_INFO("GEOMWARS: GPU plugin '{}', Vulkan backend", config.gpu_plugin);
        // readback_resolve stays the SDK's default ("none") until a feature that reads a
        // resolve back on the CPU is found (DOAX2 needed "some" for its photos, LOTR Conquest
        // "fast" for its exposure). The value in force is logged so a run's log says which;
        // --readback_resolve=none|some|fast|full on the command line sets it (plugin options
        // need the = form, docs/PLAN.md).
        REXLOG_INFO("GEOMWARS: resolve readback '{}'", rex::cvar::GetFlagByName("readback_resolve"));
      } else {
        REXLOG_ERROR("GEOMWARS: GPU plugin '{}' has no Vulkan backend", config.gpu_plugin);
      }
    }

    geomwars::audio_dump::Install(config);  // --geomwars_audio_dump <file>: records the audio output

    // An Xbox Live Arcade title asks XamContentGetLicenseMask whether it is bought; the SDK's
    // license_mask defaults to 0, which is the trial (a time limit, "Unlock full game" nags).
    // Your own package is your licence: bit 0 set means the full game. --license_mask=<n> on
    // the command line still wins (0 keeps the trial, to test that path).
    if (rex::cvar::GetFlagByName("license_mask") == "0") {
      rex::cvar::SetFlagByName("license_mask", "1");
      REXLOG_INFO("GEOMWARS: license_mask 1 (the full game; --license_mask=0 for the trial)");
    }

    if (config.input_factory) {
      config.input_factory = [base = config.input_factory](bool tool_mode) {
        auto input = base(tool_mode);
        if (auto* system = dynamic_cast<rex::input::InputSystem*>(input.get())) {
          if (REXCVAR_GET(geomwars_shared_controllers)) {
            system->SetDeviceAssignment(std::make_unique<rex::input::SharedAssignment>());
            REXLOG_INFO("GEOMWARS: every controller drives player 1");
          } else {
            system->SetDeviceAssignment(geomwars::autopilot::CreatePlayerSlots());
            REXLOG_INFO("GEOMWARS: one controller per player slot");
          }
          if (auto autopilot = geomwars::autopilot::Create()) system->AddDriver(std::move(autopilot));
        }
        return input;
      };
    }
  }

  void OnPostSetup() override {
    if (auto* w = window()) w->SetTitle("Geometry Wars: Retro Evolved (Xbox 360)");
    // Under RenderDoc (tools/rdoc_capture.ps1 -Play), capture the next two game frames.
    rex::ui::RegisterBind("bind_geomwars_rdoc_capture", "F9",
                          "Capture the next game frames in RenderDoc",
                          [] { GeomWarsRequestRenderDocCapture(); });
  }

  void OnConfigureFonts(ImFontAtlas* atlas) override { geomwars::ui::AddFonts(atlas); }
  void OnConfigureStyle(ImGuiStyle& imgui_style, rex::ui::Style& ui_style) override {
    (void)ui_style;
    geomwars::ui::ScaleStyle(imgui_style);
  }

  void OnCreateDialogs(rex::ui::ImGuiDrawer* drawer) override {
    pad_bridge_ = geomwars::ui::CreatePadBridge(drawer);
  }
  void OnShutdown() override { pad_bridge_.reset(); }

 private:
  std::unique_ptr<rex::ui::ImGuiDialog> pad_bridge_;
};
