// Simulated industrial program, a stand-in for real plant software. No network, no hardware.
//
// Sensitive strings (database connection string, API key, license keys, error messages, and the
// function names used in logs) are written with SECRET(...).
//   normal build:   SECRET encrypts the text with ADVobfuscator, fixed-parameter XOR (key 0x5A).
//   control build:  -DPLAIN_STRINGS, the same text as plain literals.
// Both builds must print the same output. ../verify_pair.ps1 checks the binaries.

#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>
#include <advobfuscator/string.h>

namespace {

using andrivet::advobfuscator::DataAlgorithm;
using andrivet::advobfuscator::KeyAlgorithm;
using andrivet::advobfuscator::ObfuscatedString;
using andrivet::advobfuscator::Parameters;

#ifdef PLAIN_STRINGS
#define SECRET(text) std::string(text)
#else
constexpr Parameters kXor{.key = 0x5A, .key_algo = KeyAlgorithm::IDENTITY, .data_algo = DataAlgorithm::XOR};
#define SECRET(text) (ObfuscatedString(text, kXor).decode())
#endif

enum class Tier { None, Trial, Enterprise };

Tier license_tier(const std::string& key) {
  if (key == SECRET("LIC-ENT-2026-DEMO-7731-XQ")) return Tier::Enterprise;
  if (key == SECRET("LIC-TRIAL-2026-DEMO-0000")) return Tier::Trial;
  return Tier::None;
}

int count_fields(const std::string& connection) {
  int n = 0;
  for (char c : connection) {
    if (c == ';') ++n;
  }
  return n;
}

std::uint32_t fnv1a(const std::string& s) {
  std::uint32_t h = 2166136261u;
  for (unsigned char c : s) {
    h ^= c;
    h *= 16777619u;
  }
  return h;
}

// Linear setpoint ramp from start to target in `steps` points (steps >= 2).
std::vector<double> setpoint_ramp(double start, double target, int steps) {
  std::vector<double> out;
  for (int i = 0; i < steps; ++i) {
    out.push_back(start + (target - start) * i / (steps - 1));
  }
  return out;
}

// Returns true when every reading is within `tolerance` of `reference`. `max_drift` receives the largest drift.
bool validate_calibration(const std::vector<double>& readings, double reference, double tolerance, double& max_drift) {
  max_drift = 0.0;
  for (double r : readings) {
    double d = r - reference;
    if (d < 0) d = -d;
    if (d > max_drift) max_drift = d;
  }
  return max_drift <= tolerance;
}

// Simulated historian commit. Returns 0 on acknowledgement, otherwise an error code.
int commit_batch(bool historian_ack) { return historian_ack ? 0 : 5002; }

}  // namespace

int main() {
  const std::string connection = SECRET("Server=tcp:plant-db.internal.example.invalid,1433;Database=HMI_PROD;User Id=svc_hmi;Password=Pl@nt-Secret-9931;");
  std::printf("[config] database connection loaded, fields=%d\n", count_fields(connection));
  std::printf("[api] key fingerprint 0x%08x\n", fnv1a(SECRET("ak_live_7f3c9e21b0d84a6c_DEMO")));

  const Tier enterprise = license_tier(SECRET("LIC-ENT-2026-DEMO-7731-XQ"));
  std::printf("[license] tier=%s\n", enterprise == Tier::Enterprise ? "enterprise" : "other");
  const Tier trial = license_tier(SECRET("LIC-TRIAL-2026-DEMO-0000"));
  if (trial != Tier::Enterprise) {
    std::printf("%s\n", SECRET("ERR_LICENSE_NOT_ENTITLED_DEMO_E101: feature ADVANCED_TAGS requires enterprise license").c_str());
  }

  std::printf("[%s] steps=5:", SECRET("CalculateSetpointRamp").c_str());
  for (double v : setpoint_ramp(10.0, 40.0, 5)) std::printf(" %.2f", v);
  std::printf("\n");

  double drift = 0.0;
  const bool good = validate_calibration({100.1, 99.8, 100.3, 99.9}, 100.0, 1.0, drift);
  std::printf("[%s] ok=%d max_drift=%.2f\n", SECRET("ValidateSensorCalibration").c_str(), good ? 1 : 0, drift);
  if (!validate_calibration({100.2, 103.1, 99.7}, 100.0, 1.0, drift)) {
    std::printf("%s (max_drift=%.2f)\n", SECRET("ERR_CALIBRATION_OUT_OF_RANGE_DEMO_4410: sensor drift exceeds tolerance").c_str(), drift);
  }

  const int rc = commit_batch(false);
  std::printf("[%s] rc=%d\n", SECRET("CommitBatchToHistorian").c_str(), rc);
  if (rc != 0) {
    std::printf("%s\n", SECRET("ERR_HISTORIAN_TIMEOUT_DEMO_5002: historian did not acknowledge batch").c_str());
  }
  return 0;
}
