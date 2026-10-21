// The wallpaper of every page: a mosaic of flat drawings (fruits and vegetables loose, on their
// plants and trees, wrapped and unwrapped) on the white background. It is drawn once, in the layout;
// the content of each page sits on top of it. It is only decoration: hidden from screen readers,
// fixed behind the content, it never takes a click. Strength: opacity-25 (soft colours, never loud).
//
// The tile is 480 x 480. Drawings stay at least 20px away from its edges, so that none is cut where
// the tile repeats.

export default function Decoration() {
  return (
    <svg aria-hidden="true" focusable="false" className="pointer-events-none fixed inset-0 z-0 h-full w-full opacity-25">
      <defs>
        {/* Fruits, drawn around the point (0, 0), about 28px wide */}
        <g id="tomato">
          <circle r="14" fill="#e5533d" />
          <circle cx="-5" cy="-5" r="3.5" fill="#fff" opacity=".35" />
          <ellipse cy="-12" rx="7" ry="3" fill="#3f7d4e" />
          <path d="M0 -12v-5" stroke="#3f7d4e" strokeWidth="2.5" strokeLinecap="round" />
        </g>
        <g id="orange">
          <circle r="14" fill="#f4a03a" />
          <circle cx="-5" cy="-5" r="3.5" fill="#fff" opacity=".3" />
          <ellipse cx="6" cy="-13" rx="6" ry="3" fill="#5fa56a" transform="rotate(-25 6 -13)" />
        </g>
        <g id="apple">
          <path d="M0 -10C8 -16 18 -8 16 4C14 14 6 18 0 15C-6 18 -14 14 -16 4C-18 -8 -8 -16 0 -10Z" fill="#d9534f" />
          <path d="M0 -10q1 -6 5 -8" stroke="#6b4a2f" strokeWidth="2.5" fill="none" strokeLinecap="round" />
          <ellipse cx="7" cy="-15" rx="5" ry="2.5" fill="#5fa56a" transform="rotate(-20 7 -15)" />
          <circle cx="-6" cy="-3" r="3" fill="#fff" opacity=".3" />
        </g>
        <g id="potato">
          <ellipse rx="18" ry="12" fill="#c9a36b" transform="rotate(-15)" />
          <circle cx="-6" cy="-2" r="1.8" fill="#a67c4a" />
          <circle cx="5" cy="3" r="1.8" fill="#a67c4a" />
          <circle cx="9" cy="-4" r="1.5" fill="#a67c4a" />
        </g>

        {/* A branch with three tomatoes, about 125 x 80 */}
        <g id="tomato-branch">
          <path d="M0 0L110 44" stroke="#3f7d4e" strokeWidth="4" strokeLinecap="round" />
          <ellipse cx="22" cy="-2" rx="13" ry="5.5" fill="#5fa56a" transform="rotate(-35 22 -2)" />
          <ellipse cx="58" cy="12" rx="13" ry="5.5" fill="#5fa56a" transform="rotate(-30 58 12)" />
          <path d="M30 12v8M64 26v8M96 38v8" stroke="#3f7d4e" strokeWidth="2.5" strokeLinecap="round" />
          <use href="#tomato" transform="translate(30 34)" />
          <use href="#tomato" transform="translate(64 48) scale(.9)" />
          <use href="#tomato" transform="translate(96 60) scale(.85)" />
        </g>

        {/* An orange tree and an apple tree, about 100 x 100 */}
        <g id="orange-tree">
          <rect x="-5" y="22" width="10" height="28" rx="2" fill="#9a6b43" />
          <circle cx="-18" cy="6" r="18" fill="#6bb273" />
          <circle cx="18" cy="6" r="18" fill="#6bb273" />
          <circle cx="0" cy="-12" r="20" fill="#6bb273" />
          <circle cx="0" cy="6" r="22" fill="#6bb273" />
          <use href="#orange" transform="translate(-14 0) scale(.5)" />
          <use href="#orange" transform="translate(12 -10) scale(.5)" />
          <use href="#orange" transform="translate(4 12) scale(.5)" />
          <use href="#orange" transform="translate(-22 14) scale(.5)" />
          <use href="#orange" transform="translate(22 10) scale(.5)" />
          <use href="#orange" transform="translate(-4 -20) scale(.5)" />
        </g>
        <g id="apple-tree">
          <rect x="-5" y="22" width="10" height="28" rx="2" fill="#9a6b43" />
          <circle cx="-18" cy="6" r="18" fill="#7fb96f" />
          <circle cx="18" cy="6" r="18" fill="#7fb96f" />
          <circle cx="0" cy="-12" r="20" fill="#7fb96f" />
          <circle cx="0" cy="6" r="22" fill="#7fb96f" />
          <use href="#apple" transform="translate(-14 0) scale(.45)" />
          <use href="#apple" transform="translate(12 -8) scale(.45)" />
          <use href="#apple" transform="translate(6 14) scale(.45)" />
          <use href="#apple" transform="translate(-22 14) scale(.45)" />
          <use href="#apple" transform="translate(22 12) scale(.45)" />
        </g>

        {/* A wooden crate full of fruit, about 125 x 60 */}
        <g id="crate">
          <use href="#tomato" transform="translate(16 8)" />
          <use href="#tomato" transform="translate(44 8)" />
          <use href="#orange" transform="translate(72 8)" />
          <use href="#tomato" transform="translate(100 8)" />
          <rect x="-4" y="12" width="124" height="46" rx="5" fill="#c68e5a" stroke="#8f5d2f" strokeWidth="2" />
          <path d="M-4 27H120M-4 42H120M14 12v46M102 12v46" stroke="#a8703f" strokeWidth="3" />
        </g>

        {/* A tray of oranges under a film, about 120 x 50 */}
        <g id="tray">
          <use href="#orange" transform="translate(20 26)" />
          <use href="#orange" transform="translate(52 26)" />
          <use href="#orange" transform="translate(84 26)" />
          <rect x="-6" y="30" width="116" height="22" rx="6" fill="#e6d3a8" stroke="#b89b6a" strokeWidth="2" />
          <rect x="-8" y="4" width="120" height="48" rx="14" fill="#cfe3ee" opacity=".55" stroke="#6fa3bf" strokeWidth="2.5" />
          <path d="M8 12Q20 8 34 11" stroke="#fff" strokeWidth="3" strokeLinecap="round" opacity=".7" />
        </g>

        {/* A cardboard box with a window, about 96 x 64 */}
        <g id="box">
          <rect width="96" height="64" rx="4" fill="#d9b382" stroke="#b48a52" strokeWidth="2" />
          <path d="M0 14H96V4a4 4 0 0 0-4-4H4a4 4 0 0 0-4 4Z" fill="#c9a06b" stroke="#b48a52" strokeWidth="2" />
          <rect x="40" width="16" height="14" fill="#e8cfa5" />
          <rect x="14" y="24" width="68" height="28" rx="5" fill="#fff" opacity=".7" />
          <use href="#orange" transform="translate(32 40) scale(.8)" />
          <use href="#orange" transform="translate(58 40) scale(.8)" />
        </g>

        <pattern id="wallpaper" width="480" height="480" patternUnits="userSpaceOnUse" patternTransform="translate(0 44)">
          <use href="#tomato-branch" transform="translate(28 50) rotate(-8)" />
          <use href="#orange-tree" transform="translate(305 75)" />
          <use href="#tomato" transform="translate(205 62)" />
          <use href="#orange" transform="translate(262 165) scale(.9)" />
          <use href="#box" transform="translate(40 215)" />
          <use href="#tray" transform="translate(190 205)" />
          <use href="#crate" transform="translate(335 205)" />
          <use href="#tomato" transform="translate(42 322)" />
          <use href="#apple" transform="translate(155 296)" />
          <use href="#apple-tree" transform="translate(110 385)" />
          <use href="#potato" transform="translate(400 325) rotate(10)" />
          <use href="#potato" transform="translate(428 352) rotate(-20) scale(.85)" />
          <use href="#orange" transform="translate(300 315)" />
          <use href="#tray" transform="translate(200 395) scale(.9)" />
          <use href="#tomato-branch" transform="translate(430 440) rotate(165) scale(.85)" />
        </pattern>
      </defs>
      <rect width="100%" height="100%" fill="url(#wallpaper)" />
    </svg>
  )
}
