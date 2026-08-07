package calc

// Sum returns a + b. Intentionally wrong for eval fault injection.
func Sum(a, b int) int {
	return a + b + 1
}
