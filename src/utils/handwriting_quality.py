import cv2
import numpy as np


def assess_handwriting_quality(image_path: str) -> dict:
    """
    Assess the legibility and quality of handwritten content in an image.

    Uses OpenCV image processing to evaluate:
    - Contrast ratio between ink and background
    - Image degradation (fading, smudges, stains)
    - Blur and focus quality
    - Overall image quality score

    Returns a dict with:
    - legibility_score (0-100): Overall readability estimate
    - contrast_ratio: Ink vs background contrast (higher = better)
    - degradation_score (0-100): Amount of degradation (0 = clean, 100 = heavily degraded)
    - blur_detected: Boolean - True if image is blurry
    - overall_quality: Composite quality score (0-100)
    - confidence_recommendation: "HIGH", "MEDIUM", or "LOW" confidence level
    - details: Explanation of assessment

    Mapping:
    - legibility_score > 75: confidence = "HIGH"
    - legibility_score 50-75: confidence = "MEDIUM"
    - legibility_score < 50: confidence = "LOW"
    """
    img = cv2.imread(image_path)
    if img is None:
        return {
            "legibility_score": 0,
            "contrast_ratio": 0.0,
            "degradation_score": 100,
            "blur_detected": True,
            "overall_quality": 0,
            "confidence_recommendation": "LOW",
            "details": f"Could not load image at path: {image_path}",
        }

    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    # ── Contrast ratio ────────────────────────────────────────────────────────
    # Otsu threshold splits ink (dark) from background (light)
    _, thresh = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    background_pixels = gray[thresh == 255]
    ink_pixels = gray[thresh == 0]

    if len(ink_pixels) == 0 or len(background_pixels) == 0:
        contrast_ratio = 0.0
    else:
        bg_mean = float(np.mean(background_pixels))
        ink_mean = float(np.mean(ink_pixels))
        contrast_ratio = round((bg_mean - ink_mean) / 255.0 * 100, 1)

    contrast_score = min(100.0, max(0.0, contrast_ratio * 1.5))

    # ── Blur detection ────────────────────────────────────────────────────────
    # Laplacian variance: high = sharp edges, low = blurry
    laplacian_var = float(cv2.Laplacian(gray, cv2.CV_64F).var())
    blur_detected = laplacian_var < 100.0
    # Normalize: 0 → 0 score, 500+ → 100 score
    sharpness_score = min(100.0, laplacian_var / 5.0)

    # ── Degradation score ─────────────────────────────────────────────────────
    # Estimate noise via difference between image and a Gaussian-smoothed version.
    # High residual variance = noise/stains/smudges = degradation.
    smoothed = cv2.GaussianBlur(gray, (5, 5), 0)
    noise = gray.astype(np.float32) - smoothed.astype(np.float32)
    noise_std = float(np.std(noise))
    # noise_std of ~5 = clean, ~20+ = heavily degraded
    degradation_score = round(min(100.0, noise_std * 5.0), 1)
    cleanliness_score = max(0.0, 100.0 - degradation_score)

    # ── Composite legibility score ────────────────────────────────────────────
    # Weighted: contrast 40%, sharpness 40%, cleanliness 20%
    legibility_score = round(
        contrast_score * 0.40 + sharpness_score * 0.40 + cleanliness_score * 0.20, 1
    )
    overall_quality = round(legibility_score, 1)

    # ── Confidence recommendation ─────────────────────────────────────────────
    if legibility_score > 75:
        confidence_recommendation = "HIGH"
    elif legibility_score >= 50:
        confidence_recommendation = "MEDIUM"
    else:
        confidence_recommendation = "LOW"

    # ── Human-readable details ────────────────────────────────────────────────
    parts = []
    if contrast_score < 40:
        parts.append("low ink-to-background contrast (faded or light ink)")
    if blur_detected:
        parts.append(f"blurry image (Laplacian variance {laplacian_var:.1f} < 100)")
    if degradation_score > 40:
        parts.append(f"significant noise/degradation (score {degradation_score})")
    details = "; ".join(parts) if parts else "Image quality is good."

    return {
        "legibility_score": legibility_score,
        "contrast_ratio": contrast_ratio,
        "degradation_score": degradation_score,
        "blur_detected": blur_detected,
        "overall_quality": overall_quality,
        "confidence_recommendation": confidence_recommendation,
        "details": details,
    }
