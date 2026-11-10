#include "app/app.h"
namespace game { void KeyboardPad(int port, input::Pad& p); void InstallCaptureSignal(); }
const app::GameInfo app::kGame = {
    .title = L"Unreal Championship 2: The Liandri Conflict",
    .short_title = L"Unreal Championship 2", .name = L"UnrealChampionship2",
    .log = "uc2", .settings = "settings.toml", .splash = L"splash",
    .missing = L"Put your legally acquired game files in assets/ beside default.xbe.",
    .images = {{"default.xbe", "UnrealChampionship2"}},
    .options = {}, .load = nullptr, .save = nullptr,
    .init = game::InstallCaptureSignal, .loaded = nullptr, .window = nullptr,
    .message = nullptr, .ui = nullptr, .pad = game::KeyboardPad, .rumble = nullptr,
};
