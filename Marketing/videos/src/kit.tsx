// Shared pieces for Cave Cals videos: brand colors, cave-wall background, headlines,
// mascots, a phone showing a real app screenshot, and a scene sequencer.
import {AbsoluteFill, Img, spring, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {TransitionSeries, linearTiming} from '@remotion/transitions';
import {fade} from '@remotion/transitions/fade';
import {slide} from '@remotion/transitions/slide';
import {loadFont} from '@remotion/fonts';

loadFont({family: 'Schoolbell', url: staticFile('brand/Schoolbell-Regular.ttf')});

export const INK = '#2B211A';
export const ORANGE = '#C4531B'; // caveOrange
export const CREAM = '#FBF8F2';
export const SURFACE = '#FBF6EC'; // caveSurface, the app's row cards

export type Video = {id: string; component: React.FC; durationInFrames: number; width?: number; height?: number};

/** A pose from `brand/characters`, e.g. `zog/zog-thumbs-up` or `before-after/zog-habit-after`. */
export const character = (path: string) => staticFile(`brand/characters/${path}.png`);
/** A 1320 × 2868 app screenshot from `app-store-screenshots/raw-1.2`, e.g. `home`. */
export const screen = (name: string) => staticFile(`screens/${name}.png`);

export const usePop = (delay: number, damping = 12) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  return spring({frame: frame - delay, fps, config: {damping}});
};

// Schoolbell has no bold weight, so a stroke in the text color thickens it (like the app's InkBoldText).
export const ink = (size: number, color: string): React.CSSProperties => ({
  fontFamily: 'Schoolbell',
  fontSize: size,
  lineHeight: 1.05,
  color,
  WebkitTextStroke: `${size * 0.03}px ${color}`,
});

/** Centered Schoolbell lines whose words pop in one after another. */
export const Headline: React.FC<{lines: string[]; size?: number; top?: number; delay?: number; color?: string}> = ({
  lines,
  size = 150,
  top = 160,
  delay = 0,
  color = INK,
}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  let word = 0;
  return (
    <div style={{position: 'absolute', top, left: 50, right: 50, textAlign: 'center', ...ink(size, color)}}>
      {lines.map((line, lineIndex) => (
        <div key={lineIndex}>
          {line.split(' ').map((text, index) => {
            const p = spring({frame: frame - delay - word++ * 4, fps, config: {damping: 11}});
            return (
              <span
                key={index}
                style={{
                  display: 'inline-block',
                  margin: `0 ${size * 0.11}px`,
                  opacity: Math.min(1, p * 2),
                  transform: `translateY(${(1 - p) * 60}px) scale(${0.6 + 0.4 * p})`,
                }}
              >
                {text}
              </span>
            );
          })}
        </div>
      ))}
    </div>
  );
};

/** A mascot pose that gently bobs. Slides in from the side by `from` pixels, or jumps up from below when `from` is 0. */
export const Character: React.FC<{src: string; height: number; left: number; bottom: number; delay?: number; from?: number; bob?: number}> = ({
  src,
  height,
  left,
  bottom,
  delay = 0,
  from = -700,
  bob = 6,
}) => {
  const frame = useCurrentFrame();
  const p = usePop(delay);
  return (
    <Img
      src={src}
      style={{
        position: 'absolute',
        left,
        bottom,
        height,
        filter: 'drop-shadow(0 18px 22px rgba(60, 30, 10, 0.25))',
        transform: `translate(${(1 - p) * from}px, ${(from === 0 ? (1 - p) * 1000 : 0) + Math.sin(frame / 7) * bob}px) rotate(${Math.sin(frame / 11) * 1.5}deg)`,
      }}
    />
  );
};

/** A phone that flies up showing a screenshot. Children overlay the screen, placed in percentages of it. */
export const Phone: React.FC<{src: string; delay?: number; left?: number; top?: number; width?: number; children?: React.ReactNode}> = ({
  src,
  delay = 0,
  left = 500,
  top = 540,
  width = 540,
  children,
}) => {
  const p = usePop(delay, 14);
  const pad = width * 0.035;
  const screenWidth = width - pad * 2;
  return (
    <div
      style={{
        position: 'absolute',
        left,
        top,
        width,
        padding: pad,
        borderRadius: width * 0.15,
        background: '#1D1814',
        boxShadow: '0 40px 90px rgba(60, 30, 10, 0.35)',
        transform: `translateY(${(1 - p) * 1400}px) rotate(${(1 - p) * 8}deg)`,
      }}
    >
      <div style={{position: 'relative', width: screenWidth, height: (screenWidth * 2868) / 1320, borderRadius: width * 0.12, overflow: 'hidden'}}>
        <Img src={src} style={{width: '100%', height: '100%', display: 'block'}} />
        {children}
      </div>
    </div>
  );
};

/** A cream card with an orange border that pops in. */
export const Card: React.FC<{left: number; top: number; width: number; delay: number; rotate?: number; children: React.ReactNode}> = ({
  left,
  top,
  width,
  delay,
  rotate = -3,
  children,
}) => {
  const p = usePop(delay, 10);
  return (
    <div
      style={{
        position: 'absolute',
        left,
        top,
        width,
        padding: '28px 30px',
        background: CREAM,
        border: `6px solid ${ORANGE}`,
        borderRadius: 36,
        boxShadow: '0 20px 40px rgba(60, 30, 10, 0.2)',
        textAlign: 'center',
        opacity: Math.min(1, p * 3),
        transform: `scale(${p}) rotate(${rotate}deg)`,
      }}
    >
      {children}
    </div>
  );
};

export type Scene = {component: React.FC; frames: number; enter?: 'slide' | 'fade'};

const TRANSITION = 15;

/** Neighboring scenes overlap during each transition, so the total is shorter than the sum of the scenes. */
export const sceneFrames = (scenes: Scene[]) => scenes.reduce((sum, scene) => sum + scene.frames, 0) - TRANSITION * (scenes.length - 1);

/** Plays scenes over the slowly zooming cave wall; each scene after the first slides in from the right or fades in. */
export const CaveWallScenes: React.FC<{scenes: Scene[]}> = ({scenes}) => {
  const frame = useCurrentFrame();
  const timing = linearTiming({durationInFrames: TRANSITION});
  return (
    <AbsoluteFill style={{backgroundColor: CREAM}}>
      <Img
        src={staticFile('brand/cave-wall-bg.png')}
        style={{width: '100%', height: '100%', objectFit: 'cover', transform: `scale(${1.02 + (frame / sceneFrames(scenes)) * 0.06})`}}
      />
      <TransitionSeries>
        {scenes.flatMap(({component: Scene, frames, enter = 'slide'}, index) => [
          ...(index > 0
            ? [
                <TransitionSeries.Transition
                  key={`t${index}`}
                  presentation={enter === 'fade' ? fade() : slide({direction: 'from-right'})}
                  timing={timing}
                />,
              ]
            : []),
          <TransitionSeries.Sequence key={`s${index}`} durationInFrames={frames}>
            <Scene />
          </TransitionSeries.Sequence>,
        ])}
      </TransitionSeries>
    </AbsoluteFill>
  );
};

/** Closing card: app icon, name, tagline, a mascot pose and a call to action. */
export const EndCard: React.FC<{pose?: string; tagline?: string; cta?: string}> = ({
  pose = 'together/together-high-five',
  tagline = 'Me eat. App count.',
  cta = 'Free on the App Store',
}) => {
  const icon = usePop(4, 10);
  const pill = usePop(48, 12);
  return (
    <AbsoluteFill>
      <Img
        src={staticFile('brand/app-icon.png')}
        style={{
          position: 'absolute',
          left: 430,
          top: 150,
          width: 220,
          borderRadius: 50,
          boxShadow: '0 20px 40px rgba(60, 30, 10, 0.25)',
          transform: `scale(${icon}) rotate(${(1 - icon) * -30}deg)`,
        }}
      />
      <Headline lines={['Cave Cals']} size={160} top={400} delay={12} />
      <Headline lines={[tagline]} size={84} top={590} delay={24} color={ORANGE} />
      <Character src={character(pose)} height={760} left={150} bottom={420} delay={30} from={0} bob={8} />
      <div
        style={{
          position: 'absolute',
          left: 190,
          right: 190,
          top: 1530,
          padding: '26px 0',
          borderRadius: 999,
          background: ORANGE,
          textAlign: 'center',
          transform: `scale(${pill})`,
          ...ink(64, 'white'),
        }}
      >
        {cta}
      </div>
    </AbsoluteFill>
  );
};
