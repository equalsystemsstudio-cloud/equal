// Convert SVG assets to PNG/JPG for Google Play
// Usage: node tools/convert_svgs_to_png.js

const fs = require('fs');
const path = require('path');
const sharp = require('sharp');

const projectRoot = 'C:/equal';
const outputsRoot = path.join(projectRoot, 'store', 'exports');

const paths = {
  featureSvg: path.join(projectRoot, 'assets', 'images', 'store_feature_graphic.svg'),
  appIconSvg: path.join(projectRoot, 'assets', 'images', 'app_icon.svg'),
  screenshotsDir: path.join(projectRoot, 'store', 'screenshots', 'phone'),
  tabletScreenshotsDir: path.join(projectRoot, 'store', 'screenshots', 'tablet'),
};

const sizes = {
  feature: { width: 1024, height: 500 },
  appIcon: { width: 512, height: 512 },
  phoneScreenshot: { width: 1080, height: 1920 },
  tabletScreenshot: { width: 2048, height: 1536 },
};

function ensureDir(p) {
  fs.mkdirSync(p, { recursive: true });
}

async function convertSvgToPng(svgPath, outPath, width, height) {
  const svg = fs.readFileSync(svgPath);
  await sharp(svg, { density: 300 })
    .resize(width, height, { fit: 'cover' })
    .png({ quality: 95 })
    .toFile(outPath);
  console.log(`Exported: ${outPath}`);
}

async function exportFeature() {
  const outDir = path.join(outputsRoot, 'play', 'feature');
  ensureDir(outDir);
  const outPath = path.join(outDir, 'feature_graphic_1024x500.png');
  await convertSvgToPng(paths.featureSvg, outPath, sizes.feature.width, sizes.feature.height);
}

async function exportIcon() {
  const outDir = path.join(outputsRoot, 'play', 'icons');
  ensureDir(outDir);
  const outPath = path.join(outDir, 'app_icon_512x512.png');
  await convertSvgToPng(paths.appIconSvg, outPath, sizes.appIcon.width, sizes.appIcon.height);
}

async function exportPhoneScreenshots() {
  const outDir = path.join(outputsRoot, 'play', 'screenshots', 'phone');
  ensureDir(outDir);
  const files = fs.readdirSync(paths.screenshotsDir).filter(f => f.endsWith('.svg'));
  for (const f of files) {
    const name = path.parse(f).name;
    const outPath = path.join(outDir, `${name}_1080x1920.png`);
    await convertSvgToPng(path.join(paths.screenshotsDir, f), outPath, sizes.phoneScreenshot.width, sizes.phoneScreenshot.height);
  }
}

async function exportTabletScreenshots() {
  const outDir = path.join(outputsRoot, 'play', 'screenshots', 'tablet');
  ensureDir(outDir);
  const files = fs.readdirSync(paths.tabletScreenshotsDir).filter(f => f.endsWith('.svg'));
  for (const f of files) {
    const name = path.parse(f).name;
    const outPath = path.join(outDir, `${name}_2048x1536.png`);
    await convertSvgToPng(path.join(paths.tabletScreenshotsDir, f), outPath, sizes.tabletScreenshot.width, sizes.tabletScreenshot.height);
  }
}

async function main() {
  ensureDir(outputsRoot);
  await exportFeature();
  await exportIcon();
  await exportPhoneScreenshots();
  await exportTabletScreenshots();
  console.log('All exports completed.');
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});