// "Snap it. Say it. Tap it. Done." 20 s, 1080 × 1920. Catalog entry in ../../README.md.
import {AbsoluteFill, Img, interpolate, useCurrentFrame} from 'remotion';
import {Card, CaveWallScenes, Character, EndCard, Headline, INK, ORANGE, Phone, SURFACE, Scene, Video, character, ink, sceneFrames, screen, usePop} from '../kit';

const HookScene: React.FC = () => {
  const frame = useCurrentFrame();
  const drop = usePop(8, 9);
  const shake = Math.sin(frame * 2.6) * 22 * Math.max(0, 1 - Math.abs(frame - 22) / 14);
  return (
    <AbsoluteFill>
      <Headline lines={['Still counting', 'calories on rocks?']} size={124} top={230} delay={20} />
      <Img
        src={character('before-after/zog-habit-before')}
        style={{
          position: 'absolute',
          left: 40,
          bottom: 330,
          width: 1000,
          filter: 'drop-shadow(0 22px 26px rgba(60, 30, 10, 0.25))',
          transform: `translate(${shake}px, ${(1 - drop) * -1500}px)`,
        }}
      />
    </AbsoluteFill>
  );
};

const ScanOverlay: React.FC<{delay: number}> = ({delay}) => {
  const frame = useCurrentFrame() - delay;
  if (frame < 0) return null;
  const corner = (position: React.CSSProperties, rotate: number) => (
    <div
      style={{
        position: 'absolute',
        width: 64,
        height: 64,
        borderTop: `10px solid ${ORANGE}`,
        borderLeft: `10px solid ${ORANGE}`,
        borderTopLeftRadius: 18,
        transform: `rotate(${rotate}deg)`,
        ...position,
      }}
    />
  );
  return (
    <div
      style={{
        position: 'absolute',
        left: '12%',
        top: '21%',
        width: '76%',
        height: '46%',
        opacity: Math.min(1, frame / 8),
        transform: `scale(${1 + Math.sin(frame / 5) * 0.025})`,
      }}
    >
      {corner({left: 0, top: 0}, 0)}
      {corner({right: 0, top: 0}, 90)}
      {corner({right: 0, bottom: 0}, 180)}
      {corner({left: 0, bottom: 0}, 270)}
      <div
        style={{
          position: 'absolute',
          left: '5%',
          right: '5%',
          top: `${((frame % 36) / 36) * 100}%`,
          height: 6,
          borderRadius: 3,
          background: ORANGE,
          boxShadow: '0 0 24px 8px rgba(196, 83, 27, 0.6)',
        }}
      />
    </div>
  );
};

// The 550 is an illustration for this plate, not a real scan result.
const SnapScene: React.FC = () => (
  <AbsoluteFill>
    <Headline lines={['Snap it.']} />
    <Phone src={screen('meal-scan')} delay={4}>
      <ScanOverlay delay={24} />
    </Phone>
    <Card left={40} top={620} width={440} delay={70}>
      <div style={{...ink(80, ORANGE), whiteSpace: 'nowrap'}}>≈ 550 cals</div>
      <div style={{...ink(40, INK), marginTop: 8}}>chicken, rice, veggies</div>
    </Card>
    <Character src={character('before-after/zog-habit-after')} height={560} left={-30} bottom={110} delay={12} />
  </AbsoluteFill>
);

const VoiceRings: React.FC<{delay: number}> = ({delay}) => {
  const frame = useCurrentFrame() - delay;
  if (frame < 0) return null;
  return (
    <>
      {[0, 1, 2].map((ring) => {
        const t = ((frame + ring * 12) % 36) / 36;
        return (
          <div
            key={ring}
            style={{
              position: 'absolute',
              left: '50%',
              top: '25.8%',
              width: 260,
              height: 260,
              marginLeft: -130,
              marginTop: -130,
              borderRadius: '50%',
              border: `8px solid ${ORANGE}`,
              opacity: (1 - t) * 0.8,
              transform: `scale(${0.25 + t})`,
            }}
          />
        );
      })}
    </>
  );
};

const SPOKEN = '“Two eggs, toast and a coffee”';

const SayScene: React.FC = () => {
  const frame = useCurrentFrame();
  const typed = Math.round(interpolate(frame, [34, 84], [0, SPOKEN.length], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}));
  return (
    <AbsoluteFill>
      <Headline lines={['Say it.']} />
      <Phone src={screen('voice-log')} delay={4}>
        <VoiceRings delay={24} />
      </Phone>
      <Card left={40} top={600} width={430} delay={28} rotate={2}>
        <div style={{...ink(56, INK), textAlign: 'left', minHeight: 59 * 3}}>{SPOKEN.slice(0, typed)}</div>
      </Card>
      <Character src={character('zena/zena-voice-log')} height={700} left={10} bottom={110} delay={12} />
    </AbsoluteFill>
  );
};

// The add button flips forward to a checkmark, like the app's add confirmation.
const TapAdd: React.FC<{top: string; at: number; calories: number}> = ({top, at, calories}) => {
  const frame = useCurrentFrame() - at;
  if (frame < -12) return null;
  const press = interpolate(frame, [-12, 0, 6], [0, 1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const flip = interpolate(frame, [0, 12], [0, 180], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const rise = interpolate(frame, [4, 40], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  return (
    <div style={{position: 'absolute', left: '88.7%', top, width: 0, height: 0}}>
      <div
        style={{
          position: 'absolute',
          left: -60,
          top: -60,
          width: 120,
          height: 120,
          borderRadius: '50%',
          background: 'rgba(43, 33, 26, 0.18)',
          transform: `scale(${press})`,
        }}
      />
      {frame >= 0 && (
        <div
          style={{
            position: 'absolute',
            left: -22,
            top: -22,
            width: 44,
            height: 44,
            borderRadius: '50%',
            // After the flip, the row card's color covers the screenshot's own + button.
            background: flip < 90 ? ORANGE : SURFACE,
            color: flip < 90 ? 'white' : ORANGE,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            fontSize: 34,
            fontWeight: 900,
            transform: `rotateY(${flip < 90 ? flip : flip - 180}deg)`,
          }}
        >
          {flip < 90 ? '+' : '✓'}
        </div>
      )}
      {frame >= 4 && (
        <div
          style={{
            position: 'absolute',
            left: -170,
            top: -60 - rise * 90,
            width: 160,
            textAlign: 'right',
            opacity: 1 - rise,
            ...ink(46, ORANGE),
          }}
        >
          +{calories}
        </div>
      )}
    </div>
  );
};

const TapScene: React.FC = () => {
  const stamp = usePop(76, 8);
  return (
    <AbsoluteFill>
      <Headline lines={['Tap it.']} />
      <Phone src={screen('quick-add')} delay={4}>
        <TapAdd top="31.3%" at={36} calories={130} />
        <TapAdd top="53.1%" at={58} calories={5} />
      </Phone>
      <div
        style={{
          position: 'absolute',
          left: 50,
          top: 640,
          width: 420,
          textAlign: 'center',
          opacity: Math.min(1, stamp * 3),
          transform: `scale(${2.6 - 1.6 * stamp}) rotate(-8deg)`,
          ...ink(190, ORANGE),
        }}
      >
        Done.
      </div>
      <Character src={character('zena/zena-logged-check')} height={680} left={-10} bottom={110} delay={80} from={0} bob={10} />
    </AbsoluteFill>
  );
};

const SCENES: Scene[] = [
  {component: HookScene, frames: 115},
  {component: SnapScene, frames: 140},
  {component: SayScene, frames: 130},
  {component: TapScene, frames: 140},
  {component: () => <EndCard />, frames: 135, enter: 'fade'},
];

export const snapSayTap: Video = {
  id: 'snap-say-tap',
  component: () => <CaveWallScenes scenes={SCENES} />,
  durationInFrames: sceneFrames(SCENES),
};
