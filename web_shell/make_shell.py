"""Builds web_shell/shell.html (custom Godot web loading page) and resources/ui/splash.png."""
import base64, os, sys
from PIL import Image, ImageDraw, ImageFont

root = sys.argv[1]
font_path = os.path.join(root, "resources/Fonts/Staatliches-Regular.ttf")
body_font_path = os.path.join(root, "resources/Fonts/PT_Sans-Web-Bold.ttf")

INK = "#1c120b"; WOOD_DARK = "#3a2416"; WOOD = "#6b4428"; BARN_RED = "#a83c2a"
STRAW = "#e9b949"; CREAM = "#f4e7cc"

# ---------------------------------------------------------------- splash image
W, H = 1280, 720
img = Image.new("RGB", (W, H), WOOD_DARK)
d = ImageDraw.Draw(img)
# plank lines
for y in range(0, H, 90):
    d.rectangle([0, y, W, y + 3], fill="#2f1d11")
title = ImageFont.truetype(font_path, 132)
sub = ImageFont.truetype(font_path, 54)
def centered(text, font, y, fill, outline=10, shadow=8):
    w = d.textlength(text, font=font)
    x = (W - w) / 2
    d.text((x, y + shadow), text, font=font, fill=INK, stroke_width=outline, stroke_fill=INK)
    d.text((x, y), text, font=font, fill=fill, stroke_width=outline, stroke_fill=INK)
centered("SABONG LEGENDS", title, 205, STRAW)
centered("CLUCK COCK", sub, 380, CREAM, outline=7, shadow=6)
os.makedirs(os.path.join(root, "resources/ui"), exist_ok=True)
img.save(os.path.join(root, "resources/ui/splash.png"))

# ---------------------------------------------------------------- web shell
font_b64 = base64.b64encode(open(font_path, "rb").read()).decode()
tips = [
    "A higher dice roll strikes first and unlocks stronger cards.",
    "You discard as many cards as your roll, then refill your hand.",
    "Each round gives you 3 Taya. Most cards cost 1.",
    "Shields only last for the round you play them.",
    "Decluck's All For One cards grow with every extra Taya.",
    "Daniel comes back once at a third of his HP.",
    "Chick Yagami's poop stacks hurt more the longer they stay.",
    "Equal dice rolls mean a clash: both attacks land at once.",
]
tips_js = "[" + ",".join('"' + t.replace('"', '\\"') + '"' for t in tips) + "]"

html = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1.0">
<meta name="theme-color" content="__WOOD_DARK__">
<title>$GODOT_PROJECT_NAME</title>
<style>
@font-face { font-family: "Staatliches"; src: url(data:font/ttf;base64,__FONT__) format("truetype"); font-display: block; }
html, body, #canvas { margin: 0; padding: 0; border: 0; }
body { color: __CREAM__; background: __WOOD_DARK__; overflow: hidden; touch-action: none; }
#canvas { display: block; }
#canvas:focus { outline: none; }

#status {
	position: absolute; inset: 0; z-index: 1;
	display: flex; flex-direction: column; justify-content: center; align-items: center;
	padding: 24px; box-sizing: border-box;
	background: repeating-linear-gradient(180deg, __WOOD_DARK__ 0 86px, #2f1d11 86px 90px);
	font-family: "Staatliches", Impact, "Arial Narrow", sans-serif; text-align: center;
	visibility: hidden;
}
.title {
	font-size: clamp(42px, 9vw, 112px); line-height: .95; color: __STRAW__; letter-spacing: 1px;
	-webkit-text-stroke: clamp(4px, .8vw, 9px) __INK__; paint-order: stroke fill;
	text-shadow: 0 clamp(4px, .7vw, 8px) 0 __INK__;
}
.subtitle {
	margin-top: .2em; font-size: clamp(22px, 4vw, 48px); color: __CREAM__;
	-webkit-text-stroke: clamp(3px, .5vw, 6px) __INK__; paint-order: stroke fill;
	text-shadow: 0 4px 0 __INK__;
}
.bar {
	width: min(560px, 86vw); height: 34px; margin-top: clamp(28px, 6vh, 56px); box-sizing: border-box;
	background: __CREAM__; border: 4px solid __INK__; border-bottom-width: 9px; border-radius: 3px; overflow: hidden;
}
.bar > div { height: 100%; width: 0%; background: __BARN_RED__; transition: width .2s linear; }
.bar.busy > div { width: 35%; animation: busy 1.1s ease-in-out infinite alternate; }
@keyframes busy { from { transform: translateX(-10%); } to { transform: translateX(195%); } }
.label {
	margin-top: 14px; font-size: clamp(18px, 2.6vw, 26px); color: __CREAM__;
	-webkit-text-stroke: 3px __INK__; paint-order: stroke fill;
}
.tip {
	margin-top: clamp(18px, 4vh, 40px); max-width: min(620px, 88vw); min-height: 2.6em;
	font-family: system-ui, "Segoe UI", Roboto, sans-serif; font-weight: 600;
	font-size: clamp(14px, 2vw, 18px); line-height: 1.3; color: rgba(244,231,204,.8); transition: opacity .4s;
}
.tip b { color: __STRAW__; font-family: "Staatliches", sans-serif; font-weight: normal; letter-spacing: .5px; }
.notice {
	display: none; margin-top: 28px; max-width: min(620px, 88vw); padding: 16px 20px; box-sizing: border-box;
	background: __WOOD__; border: 4px solid __INK__; border-bottom-width: 9px; border-radius: 3px;
	font-family: system-ui, "Segoe UI", Roboto, sans-serif; font-size: 16px; line-height: 1.4; color: __CREAM__;
}
</style>
$GODOT_HEAD_INCLUDE
</head>
<body>
<canvas id="canvas">Your browser does not support the canvas tag.</canvas>
<noscript>This game needs JavaScript to run.</noscript>

<div id="status">
	<div class="title">SABONG LEGENDS</div>
	<div class="subtitle">CLUCK COCK</div>
	<div class="bar busy" id="bar"><div id="bar-fill"></div></div>
	<div class="label" id="label">LOADING...</div>
	<div class="tip" id="tip"></div>
	<div class="notice" id="notice"></div>
</div>

<script src="$GODOT_URL"></script>
<script>
const GODOT_CONFIG = $GODOT_CONFIG;
const GODOT_THREADS_ENABLED = $GODOT_THREADS_ENABLED;
const engine = new Engine(GODOT_CONFIG);

(function () {
	const overlay = document.getElementById('status');
	const bar = document.getElementById('bar');
	const fill = document.getElementById('bar-fill');
	const label = document.getElementById('label');
	const tip = document.getElementById('tip');
	const notice = document.getElementById('notice');
	const TIPS = __TIPS__;

	let tipIndex = Math.floor(Math.random() * TIPS.length);
	function showTip() {
		tip.style.opacity = 0;
		setTimeout(() => {
			tip.innerHTML = '<b>TIP</b> &nbsp;' + TIPS[tipIndex];
			tip.style.opacity = 1;
			tipIndex = (tipIndex + 1) % TIPS.length;
		}, 400);
	}
	showTip();
	const tipTimer = setInterval(showTip, 5000);

	function mb(bytes) { return (bytes / 1048576).toFixed(0); }

	function showError(err) {
		console.error(err);
		clearInterval(tipTimer);
		bar.style.display = 'none';
		tip.style.display = 'none';
		label.textContent = 'COULDN\'T START THE GAME';
		const text = err instanceof Error ? err.message : (typeof err === 'string' ? err : 'An unknown error occurred.');
		notice.textContent = text + '\n\nTry reloading the page. If it keeps happening, use an up-to-date Chrome, Edge or Firefox.';
		notice.style.whiteSpace = 'pre-line';
		notice.style.display = 'block';
	}

	overlay.style.visibility = 'visible';
	const missing = Engine.getMissingFeatures({ threads: GODOT_THREADS_ENABLED });
	if (missing.length !== 0) {
		showError('This browser is missing features the game needs:\n' + missing.join('\n'));
		return;
	}

	engine.startGame({
		onProgress: function (current, total) {
			if (current > 0 && total > 0) {
				bar.classList.remove('busy');
				const pct = Math.min(100, Math.floor(current / total * 100));
				fill.style.width = pct + '%';
				label.textContent = pct >= 100 ? 'STARTING...' : 'LOADING ' + mb(current) + ' / ' + mb(total) + ' MB';
			}
		},
	}).then(() => {
		clearInterval(tipTimer);
		overlay.remove();
	}, showError);
}());
</script>
</body>
</html>
"""
for k, v in {"__FONT__": font_b64, "__TIPS__": tips_js, "__INK__": INK, "__WOOD_DARK__": WOOD_DARK,
             "__WOOD__": WOOD, "__BARN_RED__": BARN_RED, "__STRAW__": STRAW, "__CREAM__": CREAM}.items():
    html = html.replace(k, v)
os.makedirs(os.path.join(root, "web_shell"), exist_ok=True)
open(os.path.join(root, "web_shell/shell.html"), "w", encoding="utf-8", newline="\n").write(html)
print("shell", len(html) // 1024, "KB; splash saved")
