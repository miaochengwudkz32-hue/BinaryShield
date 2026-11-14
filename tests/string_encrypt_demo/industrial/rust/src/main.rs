// Simulated industrial program, a stand-in for real plant software. No network, no hardware.
// Mirrors ../cpp/industrial.cpp.
//
// Sensitive strings are written with secret!(...).
//   normal build:   secret! expands to obfstr::obfstr!, which obfuscates the text at compile time.
//   control build:  built with `--no-default-features --features plain`, secret! is the plain literal.
// Both builds must print the same output. ../verify_pair.ps1 checks the binaries.

// black_box keeps the compiler from folding the strings away (it could otherwise turn the control build's
// constant comparisons and loops into integer constants, which would hide the plain text from the check).
// Both builds use it, so the only difference between them is how the text is stored.
#[cfg(not(feature = "plain"))]
macro_rules! secret {
    ($s:literal) => {
        std::hint::black_box(obfstr::obfstr!($s))
    };
}

#[cfg(feature = "plain")]
macro_rules! secret {
    ($s:literal) => {
        std::hint::black_box($s)
    };
}

#[derive(PartialEq)]
enum Tier {
    None,
    Trial,
    Enterprise,
}

fn license_tier(key: &str) -> Tier {
    if key == secret!("LIC-ENT-2026-DEMO-7731-XQ") {
        Tier::Enterprise
    } else if key == secret!("LIC-TRIAL-2026-DEMO-0000") {
        Tier::Trial
    } else {
        Tier::None
    }
}

fn count_fields(connection: &str) -> usize {
    connection.bytes().filter(|&b| b == b';').count()
}

fn fnv1a(s: &str) -> u32 {
    let mut h: u32 = 2166136261;
    for b in s.bytes() {
        h ^= b as u32;
        h = h.wrapping_mul(16777619);
    }
    h
}

// Linear setpoint ramp from start to target in `steps` points (steps >= 2).
fn setpoint_ramp(start: f64, target: f64, steps: usize) -> Vec<f64> {
    (0..steps)
        .map(|i| start + (target - start) * i as f64 / (steps - 1) as f64)
        .collect()
}

// Returns true when every reading is within `tolerance` of `reference`; also returns the largest drift.
fn validate_calibration(readings: &[f64], reference: f64, tolerance: f64) -> (bool, f64) {
    let mut max_drift = 0.0_f64;
    for &r in readings {
        let d = (r - reference).abs();
        if d > max_drift {
            max_drift = d;
        }
    }
    (max_drift <= tolerance, max_drift)
}

// Simulated historian commit. Returns 0 on acknowledgement, otherwise an error code.
fn commit_batch(historian_ack: bool) -> i32 {
    if historian_ack {
        0
    } else {
        5002
    }
}

fn main() {
    // obfstr's value is a temporary that must be used in the statement that creates it (see obfstr docs),
    // so the connection string is passed straight into the call, not stored in a `let`.
    println!(
        "[config] database connection loaded, fields={}",
        count_fields(secret!("Server=tcp:plant-db.internal.example.invalid,1433;Database=HMI_PROD;User Id=svc_hmi;Password=Pl@nt-Secret-9931;"))
    );
    println!("[api] key fingerprint 0x{:08x}", fnv1a(secret!("ak_live_7f3c9e21b0d84a6c_DEMO")));

    let enterprise = license_tier(secret!("LIC-ENT-2026-DEMO-7731-XQ"));
    println!(
        "[license] tier={}",
        if enterprise == Tier::Enterprise { "enterprise" } else { "other" }
    );
    let trial = license_tier(secret!("LIC-TRIAL-2026-DEMO-0000"));
    if trial != Tier::Enterprise {
        println!("{}", secret!("ERR_LICENSE_NOT_ENTITLED_DEMO_E101: feature ADVANCED_TAGS requires enterprise license"));
    }

    print!("[{}] steps=5:", secret!("CalculateSetpointRamp"));
    for v in setpoint_ramp(10.0, 40.0, 5) {
        print!(" {:.2}", v);
    }
    println!();

    let (good, drift_good) = validate_calibration(&[100.1, 99.8, 100.3, 99.9], 100.0, 1.0);
    println!("[{}] ok={} max_drift={:.2}", secret!("ValidateSensorCalibration"), good as i32, drift_good);
    let (bad_ok, drift_bad) = validate_calibration(&[100.2, 103.1, 99.7], 100.0, 1.0);
    if !bad_ok {
        println!(
            "{} (max_drift={:.2})",
            secret!("ERR_CALIBRATION_OUT_OF_RANGE_DEMO_4410: sensor drift exceeds tolerance"),
            drift_bad
        );
    }

    let rc = commit_batch(false);
    println!("[{}] rc={}", secret!("CommitBatchToHistorian"), rc);
    if rc != 0 {
        println!("{}", secret!("ERR_HISTORIAN_TIMEOUT_DEMO_5002: historian did not acknowledge batch"));
    }
}
