// A private function reached only through the public one below it, with no annotation in either.
// kcov sees the private function's lines run inside the public one's calls, so its paths are ticked
// exactly as a public function's are.

fn clamp(value: u32) u32 {
    if (value > 100) {
        return 100;
    }
    return value;
}

pub fn clampedDouble(value: u32) u32 {
    return clamp(value) * 2;
}
