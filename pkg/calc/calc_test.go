package calc

import "testing"

func TestSum(t *testing.T) {
	cases := []struct {
		a, b, want int
	}{
		{0, 0, 0},
		{2, 3, 5},
		{-1, 1, 0},
	}
	for _, tc := range cases {
		if got := Sum(tc.a, tc.b); got != tc.want {
			t.Fatalf("Sum(%d, %d) = %d, want %d", tc.a, tc.b, got, tc.want)
		}
	}
}
