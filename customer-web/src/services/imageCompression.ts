export type ImageCategory = 'vehicle' | 'rcDocument' | 'selfie' | 'profile' | 'general';

interface CompressionConfig {
  maxDimension: number;
  quality: number;
  minQuality: number;
}

const CONFIG_MAP: Record<ImageCategory, CompressionConfig> = {
  vehicle: { maxDimension: 1920, quality: 0.80, minQuality: 0.68 },
  rcDocument: { maxDimension: 2048, quality: 0.85, minQuality: 0.75 },
  selfie: { maxDimension: 1280, quality: 0.82, minQuality: 0.70 },
  profile: { maxDimension: 1024, quality: 0.82, minQuality: 0.70 },
  general: { maxDimension: 1920, quality: 0.80, minQuality: 0.68 },
};

export interface CompressionResult {
  file: File;
  originalSize: number;
  compressedSize: number;
  reductionPercentage: number;
  previewUrl: string;
}

/**
 * Compresses an image file in the browser using HTMLCanvasElement.
 * Preserves clarity, downscales if exceeds maxDimension, and only returns
 * the compressed version if it is actually smaller than the original.
 */
export async function compressImage(
  file: File,
  category: ImageCategory = 'general'
): Promise<CompressionResult> {
  const originalSize = file.size;
  const config = CONFIG_MAP[category] || CONFIG_MAP.general;

  // Don't compress tiny files (< 5KB)
  if (originalSize <= 5 * 1024) {
    return {
      file,
      originalSize,
      compressedSize: originalSize,
      reductionPercentage: 0,
      previewUrl: URL.createObjectURL(file),
    };
  }

  return new Promise((resolve) => {
    const reader = new FileReader();
    reader.onload = (e) => {
      const img = new Image();
      img.onload = () => {
        let width = img.naturalWidth || img.width;
        let height = img.naturalHeight || img.height;

        // Proportional resize
        if (width > config.maxDimension || height > config.maxDimension) {
          if (width >= height) {
            height = Math.round((height * config.maxDimension) / width);
            width = config.maxDimension;
          } else {
            width = Math.round((width * config.maxDimension) / height);
            height = config.maxDimension;
          }
        }

        const canvas = document.createElement('canvas');
        canvas.width = width;
        canvas.height = height;

        const ctx = canvas.getContext('2d');
        if (!ctx) {
          resolve({
            file,
            originalSize,
            compressedSize: originalSize,
            reductionPercentage: 0,
            previewUrl: URL.createObjectURL(file),
          });
          return;
        }

        ctx.imageSmoothingEnabled = true;
        ctx.imageSmoothingQuality = 'high';
        ctx.drawImage(img, 0, 0, width, height);

        const tryEncode = (targetCanvas: HTMLCanvasElement, q: number): Promise<Blob | null> => {
          return new Promise((res) => {
            targetCanvas.toBlob((b) => res(b), 'image/jpeg', q);
          });
        };

        (async () => {
          try {
            // First attempt with configured quality
            let blob = await tryEncode(canvas, config.quality);

            // Step-down pass 1: try minQuality if not smaller
            if ((!blob || blob.size >= originalSize) && originalSize > 8 * 1024) {
              blob = await tryEncode(canvas, config.minQuality);
            }

            // Step-down pass 2: try quality 0.58 if still not smaller
            if ((!blob || blob.size >= originalSize) && originalSize > 8 * 1024) {
              blob = await tryEncode(canvas, 0.58);
            }

            // Step-down pass 3: resize dimensions if still not smaller
            if (
              (!blob || blob.size >= originalSize) &&
              originalSize > 8 * 1024 &&
              width > 300 &&
              height > 300
            ) {
              const scaledCanvas = document.createElement('canvas');
              scaledCanvas.width = Math.round(width * 0.82);
              scaledCanvas.height = Math.round(height * 0.82);
              const scaledCtx = scaledCanvas.getContext('2d');
              if (scaledCtx) {
                scaledCtx.imageSmoothingEnabled = true;
                scaledCtx.imageSmoothingQuality = 'high';
                scaledCtx.drawImage(canvas, 0, 0, scaledCanvas.width, scaledCanvas.height);
                const scaledBlob = await tryEncode(scaledCanvas, 0.70);
                if (scaledBlob && scaledBlob.size < originalSize) {
                  blob = scaledBlob;
                }
              }
            }

            if (!blob || blob.size >= originalSize) {
              resolve({
                file,
                originalSize,
                compressedSize: originalSize,
                reductionPercentage: 0,
                previewUrl: URL.createObjectURL(file),
              });
              return;
            }

            const fileName = file.name.replace(/\.[^/.]+$/, '') + '.jpg';
            const compressedFile = new File([blob], fileName, {
              type: 'image/jpeg',
              lastModified: Date.now(),
            });

            const reductionPercentage = ((originalSize - blob.size) / originalSize) * 100;

            resolve({
              file: compressedFile,
              originalSize,
              compressedSize: blob.size,
              reductionPercentage: Math.max(0, Math.round(reductionPercentage)),
              previewUrl: URL.createObjectURL(blob),
            });
          } catch {
            resolve({
              file,
              originalSize,
              compressedSize: originalSize,
              reductionPercentage: 0,
              previewUrl: URL.createObjectURL(file),
            });
          }
        })();
      };

      img.onerror = () => {
        resolve({
          file,
          originalSize,
          compressedSize: originalSize,
          reductionPercentage: 0,
          previewUrl: URL.createObjectURL(file),
        });
      };

      img.src = e.target?.result as string;
    };

    reader.onerror = () => {
      resolve({
        file,
        originalSize,
        compressedSize: originalSize,
        reductionPercentage: 0,
        previewUrl: URL.createObjectURL(file),
      });
    };

    reader.readAsDataURL(file);
  });
}
