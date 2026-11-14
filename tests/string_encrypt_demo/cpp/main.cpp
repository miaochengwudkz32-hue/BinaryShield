// Demo: compile-time string encryption with ADVobfuscator (https://github.com/andrivet/ADVobfuscator).
//
// Each secret below is stored encrypted in the executable and decoded at run time.
// Three build modes:
//   (default)          explicit XOR parameters (fixed key 0x5A). Used for the normal build.
//   -DRANDOM_PARAMS    the library's default "_obf" literal, whose parameters are chosen at compile time
//                      from __TIME__. Kept to measure how often a secret is left in plain text.
//   -DPLAIN_STRINGS    control build with ordinary string literals. The secrets must be found in it.
// The normal build must not contain the secrets in plain text (checked by ../verify.ps1).

#include <iostream>
#include <advobfuscator/string.h>

using namespace andrivet::advobfuscator;

int main() {
#if defined(PLAIN_STRINGS)
  std::cout << "secret 1: DEMO-SECRET-ALPHA-7731 license key check\n";
  std::cout << "secret 2: https://demo-secret.example.invalid/api/v1/token\n";
  std::cout << "secret 3: ERR_DEMO_PASSWORD_INVALID_0042\n";
  std::cout << "secret 4: Hidden string literal, not visible to strings(1)\n";
#elif defined(RANDOM_PARAMS)
  static constexpr auto s1 = "DEMO-SECRET-ALPHA-7731 license key check"_obf;
  static constexpr auto s2 = "https://demo-secret.example.invalid/api/v1/token"_obf;
  static constexpr auto s3 = "ERR_DEMO_PASSWORD_INVALID_0042"_obf;
  static constexpr auto s4 = "Hidden string literal, not visible to strings(1)"_obf;
  std::cout << "secret 1: " << s1.decode() << '\n';
  std::cout << "secret 2: " << s2.decode() << '\n';
  std::cout << "secret 3: " << s3.decode() << '\n';
  std::cout << "secret 4: " << s4.decode() << '\n';
#else
  static constexpr Parameters xor_key{.key = 0x5A, .key_algo = KeyAlgorithm::IDENTITY, .data_algo = DataAlgorithm::XOR};
  static constexpr auto s1 = ObfuscatedString("DEMO-SECRET-ALPHA-7731 license key check", xor_key);
  static constexpr auto s2 = ObfuscatedString("https://demo-secret.example.invalid/api/v1/token", xor_key);
  static constexpr auto s3 = ObfuscatedString("ERR_DEMO_PASSWORD_INVALID_0042", xor_key);
  static constexpr auto s4 = ObfuscatedString("Hidden string literal, not visible to strings(1)", xor_key);
  std::cout << "secret 1: " << s1.decode() << '\n';
  std::cout << "secret 2: " << s2.decode() << '\n';
  std::cout << "secret 3: " << s3.decode() << '\n';
  std::cout << "secret 4: " << s4.decode() << '\n';
#endif
  return 0;
}
