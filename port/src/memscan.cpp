// GEOMWARS 360 - guest memory snapshots for finding game variables (memscan.h).
#define _CRT_SECURE_NO_WARNINGS
#include "memscan.h"

#include <algorithm>
#include <chrono>
#include <cstring>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <string>

#include <rex/cvar.h>
#include <rex/logging.h>
#include <rex/system/kernel_state.h>
#include <rex/system/xmemory.h>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif

REXCVAR_DEFINE_STRING(geomwars_memscan, "", "GEOMWARS",
                      "Write snapshots of the guest's committed memory into this directory "
                      "(tools/memscan.py reads them; docs/RECLINED.md R0)")
    .lifecycle(rex::cvar::Lifecycle::kInitOnly);
REXCVAR_DEFINE_INT32(geomwars_memscan_every_ms, 2000, "GEOMWARS",
                     "Milliseconds between memory snapshots (with --geomwars_memscan)")
    .lifecycle(rex::cvar::Lifecycle::kInitOnly);
REXCVAR_DEFINE_INT32(geomwars_memscan_limit, 60, "GEOMWARS",
                     "Most memory snapshots to write in one run (with --geomwars_memscan)")
    .lifecycle(rex::cvar::Lifecycle::kInitOnly);
REXCVAR_DEFINE_BOOL(geomwars_memscan_all, false, "GEOMWARS",
                    "Include guest addresses from 0xA0000000 up (the physical views) in snapshots")
    .lifecycle(rex::cvar::Lifecycle::kInitOnly);

namespace geomwars::memscan {
namespace {

using Clock = std::chrono::steady_clock;

constexpr uint64_t kChunk = 64 * 1024;
// FINDINGS.md "Game variables": sub_820CE938 seeds this block at a new game.
constexpr uint32_t kBlock = 0x820FFE80;
constexpr uint32_t kMode = 0x820FFEBC;
constexpr uint32_t kModeFlag = 0x820FFEB8;
constexpr uint32_t kIndex = 0x820FFEAC;

bool g_checked = false;
bool g_on = false;
std::filesystem::path g_dir;
Clock::time_point g_start;
Clock::time_point g_last;
int g_seq = 0;

uint32_t Be32(const uint8_t* p) {
  return (uint32_t(p[0]) << 24) | (uint32_t(p[1]) << 16) | (uint32_t(p[2]) << 8) | p[3];
}
uint64_t Be64(const uint8_t* p) { return (uint64_t(Be32(p)) << 32) | Be32(p + 4); }

bool AllZero(const uint8_t* p, size_t n) {
  size_t i = 0;
  for (; i + 8 <= n; i += 8) {
    uint64_t v;
    std::memcpy(&v, p + i, 8);
    if (v) return false;
  }
  for (; i < n; ++i) {
    if (p[i]) return false;
  }
  return true;
}

void Probe(const uint8_t* base, int seq, long long ms) {
  const uint8_t* b = base + kBlock;
  REXLOG_INFO(
      "GEOMWARS memscan {:04} t={} ms: +0 {} +8 {} +16 {} +24 {} +28 {} +32 {} | "
      "mode {:08X} flag {:02X} index {:08X}",
      seq, ms, Be64(b), Be64(b + 8), Be64(b + 16), Be32(b + 24), Be32(b + 28), Be32(b + 32),
      Be32(base + kMode), base[kModeFlag], Be32(base + kIndex));
}

#if defined(_WIN32)
void Snapshot(uint8_t* base, int seq, long long ms) {
  char name[32];
  std::snprintf(name, sizeof(name), "%04d-%lld", seq, ms);
  const std::filesystem::path dir = g_dir / name;
  std::error_code ec;
  std::filesystem::create_directories(dir, ec);
  FILE* idx = std::fopen((dir / "chunks.idx").string().c_str(), "w");
  FILE* bin = std::fopen((dir / "data.bin").string().c_str(), "wb");
  if (!idx || !bin) {
    REXLOG_ERROR("GEOMWARS memscan: cannot write {}", dir.string());
    if (idx) std::fclose(idx);
    if (bin) std::fclose(bin);
    return;
  }
  const uint64_t limit = REXCVAR_GET(geomwars_memscan_all) ? 0x100000000ull : 0xA0000000ull;
  const auto t0 = Clock::now();
  uint64_t written = 0;
  uint64_t guest = 0;
  while (guest < limit) {
    MEMORY_BASIC_INFORMATION mbi{};
    if (!VirtualQuery(base + guest, &mbi, sizeof(mbi))) break;
    const uint64_t region_start =
        static_cast<uint64_t>(reinterpret_cast<uint8_t*>(mbi.BaseAddress) - base);
    const uint64_t region_end = std::min<uint64_t>(region_start + mbi.RegionSize, limit);
    if (region_end <= guest) break;
    const DWORD prot = mbi.Protect & 0xFF;
    const bool readable = mbi.State == MEM_COMMIT && !(mbi.Protect & PAGE_GUARD) &&
                          prot != PAGE_NOACCESS && prot != 0;
    if (readable) {
      for (uint64_t a = guest; a < region_end;) {
        const uint64_t n = std::min<uint64_t>(kChunk - (a % kChunk), region_end - a);
        const uint8_t* p = base + a;
        if (!AllZero(p, size_t(n))) {
          std::fprintf(idx, "%08llX %llu\n", static_cast<unsigned long long>(a),
                       static_cast<unsigned long long>(n));
          std::fwrite(p, 1, size_t(n), bin);
          written += n;
        }
        a += n;
      }
    }
    guest = region_end;
  }
  std::fclose(idx);
  std::fclose(bin);
  const auto took = std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - t0);
  REXLOG_INFO("GEOMWARS memscan {:04}: {} MB in {} ms -> {}", seq, written >> 20, took.count(),
              dir.string());
}
#endif

}  // namespace

void OnFrame() {
  if (!g_checked) {
    g_checked = true;
    const std::string dir = REXCVAR_GET(geomwars_memscan);
    if (dir.empty()) return;
#if defined(_WIN32)
    g_on = true;
    g_dir = dir;
    g_start = g_last = Clock::now();
    REXLOG_INFO("GEOMWARS memscan: every {} ms, at most {} snapshots, into {}",
                REXCVAR_GET(geomwars_memscan_every_ms), REXCVAR_GET(geomwars_memscan_limit),
                dir);
#else
    REXLOG_INFO("GEOMWARS memscan: Windows only for now; --geomwars_memscan ignored");
#endif
    return;
  }
  if (!g_on) return;
  const auto now = Clock::now();
  if (now - g_last < std::chrono::milliseconds(REXCVAR_GET(geomwars_memscan_every_ms))) return;
  g_last = now;
  if (g_seq >= REXCVAR_GET(geomwars_memscan_limit)) {
    g_on = false;
    REXLOG_INFO("GEOMWARS memscan: limit reached, no more snapshots");
    return;
  }
  uint8_t* base = rex::system::kernel_state()->memory()->virtual_membase();
  const long long ms =
      std::chrono::duration_cast<std::chrono::milliseconds>(now - g_start).count();
  Probe(base, g_seq, ms);
#if defined(_WIN32)
  Snapshot(base, g_seq, ms);
#endif
  ++g_seq;
}

}  // namespace geomwars::memscan
