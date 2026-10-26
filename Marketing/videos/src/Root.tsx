import {Composition} from 'remotion';
import {Video} from './kit';
import {snapSayTap} from './videos/SnapSayTap';

// Every video, oldest first. Add each new one here and to the catalog in ../README.md.
const VIDEOS: Video[] = [snapSayTap];

export const RemotionRoot: React.FC = () => (
  <>
    {VIDEOS.map(({id, component, durationInFrames, width = 1080, height = 1920}) => (
      <Composition key={id} id={id} component={component} durationInFrames={durationInFrames} fps={30} width={width} height={height} />
    ))}
  </>
);
