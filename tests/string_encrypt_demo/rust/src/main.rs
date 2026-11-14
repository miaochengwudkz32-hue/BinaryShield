// Demo: compile-time string obfuscation with obfstr (https://github.com/CasualX/obfstr).
//
// Each secret below is stored obfuscated in the executable and decoded at run time.
// Build with `--no-default-features --features plain` to get a control build with ordinary string literals.
// The secrets must appear in the control build and must not appear in the normal build
// (checked by ../verify.ps1).

fn main() {
    #[cfg(not(feature = "plain"))]
    {
        println!("secret 1: {}", obfstr::obfstr!("DEMO-SECRET-ALPHA-7731 license key check"));
        println!("secret 2: {}", obfstr::obfstr!("https://demo-secret.example.invalid/api/v1/token"));
        println!("secret 3: {}", obfstr::obfstr!("ERR_DEMO_PASSWORD_INVALID_0042"));
        println!("secret 4: {}", obfstr::obfstr!("Hidden string literal, not visible to strings(1)"));
    }
    #[cfg(feature = "plain")]
    {
        println!("secret 1: {}", "DEMO-SECRET-ALPHA-7731 license key check");
        println!("secret 2: {}", "https://demo-secret.example.invalid/api/v1/token");
        println!("secret 3: {}", "ERR_DEMO_PASSWORD_INVALID_0042");
        println!("secret 4: {}", "Hidden string literal, not visible to strings(1)");
    }
}
