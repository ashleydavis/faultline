// The body of this `if` sits on the line of its own condition. That line runs whether or not the
// branch was taken, so kcov cannot tell the two apart, and the body is a bare expression with no
// room for an annotation. Moving it to a line of its own is what makes it a path a run can prove.

pub fn isLarge(value: u32) bool {
    if (value > 1000) return true;
    return false;
}
