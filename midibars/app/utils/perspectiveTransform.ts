/**
 * Perspective transformation utilities
 * Converts a trapezoid (4 points) to a rectangle using perspective warping
 */

export interface Point {
  x: number;
  y: number;
}

export interface Trapezoid {
  topLeft: Point;
  topRight: Point;
  bottomRight: Point;
  bottomLeft: Point;
}

/**
 * Calculate the perspective transformation matrix to map a trapezoid to a rectangle
 * Uses the standard perspective transformation formula
 */
export function getPerspectiveTransform(
  source: Trapezoid,
  targetWidth: number,
  targetHeight: number,
): number[] {
  // Target rectangle corners (normalized)
  const dst = [
    [0, 0],
    [targetWidth, 0],
    [targetWidth, targetHeight],
    [0, targetHeight],
  ];

  // Source trapezoid corners
  const src = [
    [source.topLeft.x, source.topLeft.y],
    [source.topRight.x, source.topRight.y],
    [source.bottomRight.x, source.bottomRight.y],
    [source.bottomLeft.x, source.bottomLeft.y],
  ];

  // Calculate perspective transformation matrix using direct linear transformation
  // We solve for the 8 parameters of the perspective transformation
  const A: number[][] = [];
  const b: number[] = [];

  for (let i = 0; i < 4; i++) {
    const [x, y] = src[i];
    const [u, v] = dst[i];

    A.push([x, y, 1, 0, 0, 0, -u * x, -u * y]);
    b.push(u);

    A.push([0, 0, 0, x, y, 1, -v * x, -v * y]);
    b.push(v);
  }

  // Solve the system of equations using Gaussian elimination
  const h = solveLinearSystem(A, b);

  // Return transformation matrix in the form [a, b, c, d, e, f, g, h]
  // where the transformation is:
  // u = (a*x + b*y + c) / (g*x + h*y + 1)
  // v = (d*x + e*y + f) / (g*x + h*y + 1)
  return h;
}

/**
 * Solve a system of linear equations using Gaussian elimination
 */
function solveLinearSystem(A: number[][], b: number[]): number[] {
  const n = A.length;
  const augmented: number[][] = A.map((row, i) => [...row, b[i]]);

  // Forward elimination
  for (let i = 0; i < n; i++) {
    // Find pivot
    let maxRow = i;
    for (let k = i + 1; k < n; k++) {
      if (Math.abs(augmented[k][i]) > Math.abs(augmented[maxRow][i])) {
        maxRow = k;
      }
    }
    [augmented[i], augmented[maxRow]] = [augmented[maxRow], augmented[i]];

    // Make all rows below this one 0 in current column
    for (let k = i + 1; k < n; k++) {
      const factor = augmented[k][i] / augmented[i][i];
      for (let j = i; j < n + 1; j++) {
        augmented[k][j] -= factor * augmented[i][j];
      }
    }
  }

  // Back substitution
  const x = new Array(n).fill(0);
  for (let i = n - 1; i >= 0; i--) {
    x[i] = augmented[i][n];
    for (let j = i + 1; j < n; j++) {
      x[i] -= augmented[i][j] * x[j];
    }
    x[i] /= augmented[i][i];
  }

  return x;
}

/**
 * Transform a point from the original trapezoid space to the warped rectangle space
 */
export function transformPoint(
  point: Point,
  transform: number[],
): Point {
  const [a, b, c, d, e, f, g, h] = transform;
  const { x, y } = point;

  const denominator = g * x + h * y + 1;
  if (Math.abs(denominator) < 1e-10) {
    return { x: 0, y: 0 };
  }

  const u = (a * x + b * y + c) / denominator;
  const v = (d * x + e * y + f) / denominator;

  return { x: u, y: v };
}

/**
 * Transform a point from the warped rectangle space back to the original trapezoid space
 */
export function inverseTransformPoint(
  point: Point,
  transform: number[],
): Point {
  const [a, b, c, d, e, f, g, h] = transform;
  const { x: u, y: v } = point;

  // Solve for x, y in the system:
  // u = (a*x + b*y + c) / (g*x + h*y + 1)
  // v = (d*x + e*y + f) / (g*x + h*y + 1)

  // Rearranging:
  // (a - g*u)*x + (b - h*u)*y = u - c
  // (d - g*v)*x + (e - h*v)*y = v - f

  const A = [
    [a - g * u, b - h * u],
    [d - g * v, e - h * v],
  ];
  const b_vec = [u - c, v - f];

  // Solve 2x2 system
  const det = A[0][0] * A[1][1] - A[0][1] * A[1][0];
  if (Math.abs(det) < 1e-10) {
    return { x: 0, y: 0 };
  }

  const x = (b_vec[0] * A[1][1] - b_vec[1] * A[0][1]) / det;
  const y = (A[0][0] * b_vec[1] - A[1][0] * b_vec[0]) / det;

  return { x, y };
}

/**
 * Calculate the width of the warped rectangle based on the trapezoid
 * Uses the average of top and bottom edge lengths
 */
export function calculateWarpedWidth(trapezoid: Trapezoid): number {
  const topWidth = Math.sqrt(
    Math.pow(trapezoid.topRight.x - trapezoid.topLeft.x, 2) +
      Math.pow(trapezoid.topRight.y - trapezoid.topLeft.y, 2),
  );
  const bottomWidth = Math.sqrt(
    Math.pow(trapezoid.bottomRight.x - trapezoid.bottomLeft.x, 2) +
      Math.pow(trapezoid.bottomRight.y - trapezoid.bottomLeft.y, 2),
  );
  return (topWidth + bottomWidth) / 2;
}

/**
 * Calculate the height of the warped rectangle based on the trapezoid
 * Uses the average of left and right edge lengths
 */
export function calculateWarpedHeight(trapezoid: Trapezoid): number {
  const leftHeight = Math.sqrt(
    Math.pow(trapezoid.bottomLeft.x - trapezoid.topLeft.x, 2) +
      Math.pow(trapezoid.bottomLeft.y - trapezoid.topLeft.y, 2),
  );
  const rightHeight = Math.sqrt(
    Math.pow(trapezoid.bottomRight.x - trapezoid.topRight.x, 2) +
      Math.pow(trapezoid.bottomRight.y - trapezoid.topRight.y, 2),
  );
  return (leftHeight + rightHeight) / 2;
}



