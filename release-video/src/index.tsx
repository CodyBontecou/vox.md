import React from 'react';
import {
  AbsoluteFill,
  Composition,
  interpolate,
  OffthreadVideo,
  registerRoot,
  Sequence,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';

const fps = 30;

const introFrames = 90;
const outroFrames = 105;

const segments = [
  {
    kind: 'text' as const,
    duration: 150,
    eyebrow: 'New in 2.8',
    title: 'Record from anywhere',
    subtitle:
      'Toggle Recording works from Shortcuts, the Action Button, and Apple Pencil squeeze. Start again to stop, transcribe, and deliver.',
    bullets: ['Background one-shot recording', 'Live Activity timer + Stop control', 'Every Capture Preset works'],
    icon: '◉',
  },
  {
    kind: 'video' as const,
    duration: 233,
    file: '01-preset-quick-access-square.mp4',
    eyebrow: 'Capture Presets',
    title: 'Switch workflows in one tap',
    subtitle:
      'Pin favorite presets, give them emoji identities, and jump between Journal, Tasks, Meeting, and Inbox without leaving Capture.',
  },
  {
    kind: 'video' as const,
    duration: 255,
    file: '02-task-send-undo-square.mp4',
    eyebrow: 'Safer Send',
    title: 'Send now. Undo if you need to.',
    subtitle:
      'Task captures stay compact, and the Sent toast can restore your capture as an editable draft for five seconds.',
  },
  {
    kind: 'video' as const,
    duration: 261,
    file: '03-capture-bar-options-square.mp4',
    eyebrow: 'Capture Bar',
    title: 'Make the Capture Bar yours',
    subtitle:
      'Choose rail side, 12/24-hour timestamps, review behavior, and optional confirmation before preset sends.',
  },
  {
    kind: 'video' as const,
    duration: 272,
    file: '04-recording-controls-square.mp4',
    eyebrow: 'Recording Controls',
    title: 'Recording controls, explained',
    subtitle:
      'Pick Add to Draft or Send Immediately, keep audio only when needed, and open contextual help right from Capture.',
  },
  {
    kind: 'video' as const,
    duration: 158,
    file: '05-image-alt-text-square.mp4',
    eyebrow: 'Private Intelligence',
    title: 'Image descriptions stay on device',
    subtitle:
      'On supported devices, Apple Intelligence can describe photos, screenshots, and sketches before Markdown delivery.',
  },
  {
    kind: 'video' as const,
    duration: 183,
    file: '06-audio-filename-template-square.mp4',
    eyebrow: 'Audio Attachments',
    title: 'Name saved audio your way',
    subtitle:
      'Each preset gets its own filename template with date, time, preset, and capture ID tokens.',
  },
];

const totalFrames = introFrames + outroFrames + segments.reduce((sum, segment) => sum + segment.duration, 0);

const colors = {
  ink: '#111827',
  muted: '#617084',
  paper: '#f8fafc',
  blue: '#2563eb',
  cyan: '#06b6d4',
  violet: '#7c3aed',
  green: '#10b981',
  dark: '#0f172a',
};

function GradientBackground() {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const drift = interpolate(frame, [0, durationInFrames], [0, 1]);

  return (
    <AbsoluteFill
      style={{
        background:
          'radial-gradient(circle at 18% 12%, rgba(59, 130, 246, 0.26), transparent 30%), radial-gradient(circle at 86% 0%, rgba(124, 58, 237, 0.22), transparent 34%), linear-gradient(180deg, #f8fafc 0%, #eef6ff 45%, #f6f7fb 100%)',
        overflow: 'hidden',
      }}
    >
      <div
        style={{
          position: 'absolute',
          width: 680,
          height: 680,
          borderRadius: '50%',
          left: -210 + drift * 70,
          top: 980 - drift * 180,
          background: 'rgba(14, 165, 233, 0.16)',
          filter: 'blur(14px)',
        }}
      />
      <div
        style={{
          position: 'absolute',
          width: 580,
          height: 580,
          borderRadius: '50%',
          right: -220 - drift * 60,
          top: 420 + drift * 100,
          background: 'rgba(16, 185, 129, 0.13)',
          filter: 'blur(18px)',
        }}
      />
      <div
        style={{
          position: 'absolute',
          inset: 38,
          border: '1px solid rgba(15, 23, 42, 0.06)',
          borderRadius: 56,
        }}
      />
    </AbsoluteFill>
  );
}

function BrandMark() {
  return (
    <div
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        gap: 14,
        color: colors.dark,
        fontWeight: 800,
        fontSize: 32,
        letterSpacing: -0.8,
      }}
    >
      <div
        style={{
          width: 48,
          height: 48,
          borderRadius: 16,
          background: 'linear-gradient(135deg, #2563eb, #06b6d4)',
          boxShadow: '0 14px 32px rgba(37,99,235,0.28)',
          display: 'grid',
          placeItems: 'center',
          color: 'white',
          fontSize: 25,
        }}
      >
        ✦
      </div>
      Vox.md
    </div>
  );
}

function Intro() {
  const frame = useCurrentFrame();
  const scale = spring({frame, fps, config: {damping: 16, stiffness: 95}});
  const y = interpolate(frame, [0, 30], [36, 0], {extrapolateRight: 'clamp'});
  const opacity = interpolate(frame, [0, 18], [0, 1], {extrapolateRight: 'clamp'});

  return (
    <AbsoluteFill style={{padding: '120px 80px', justifyContent: 'center'}}>
      <div style={{opacity, transform: `translateY(${y}px) scale(${scale})`}}>
        <BrandMark />
        <h1
          style={{
            margin: '86px 0 24px',
            fontSize: 104,
            lineHeight: 0.93,
            letterSpacing: -5,
            color: colors.dark,
          }}
        >
          Faster capture. Safer sends.
        </h1>
        <p
          style={{
            margin: 0,
            maxWidth: 780,
            color: colors.muted,
            fontSize: 36,
            lineHeight: 1.26,
            fontWeight: 550,
          }}
        >
          Vox.md 2.8 adds background recording, preset quick access, undo, continuous dictation, private image descriptions, and smarter audio filenames.
        </p>
      </div>
    </AbsoluteFill>
  );
}

function TextFeature({segment}: {segment: Extract<(typeof segments)[number], {kind: 'text'}>}) {
  const frame = useCurrentFrame();
  const enter = spring({frame, fps, config: {damping: 18, stiffness: 90}});
  const pulse = interpolate(Math.sin(frame / 11), [-1, 1], [0.9, 1.06]);

  return (
    <AbsoluteFill style={{padding: '120px 78px'}}>
      <FeatureHeader eyebrow={segment.eyebrow} title={segment.title} />
      <div
        style={{
          marginTop: 78,
          height: 780,
          borderRadius: 64,
          background: 'linear-gradient(150deg, rgba(15,23,42,0.96), rgba(30,64,175,0.92))',
          boxShadow: '0 42px 120px rgba(15,23,42,0.28)',
          border: '1px solid rgba(255,255,255,0.22)',
          display: 'flex',
          flexDirection: 'column',
          justifyContent: 'center',
          alignItems: 'center',
          color: 'white',
          transform: `scale(${0.94 + enter * 0.06})`,
          overflow: 'hidden',
          position: 'relative',
        }}
      >
        <div
          style={{
            position: 'absolute',
            inset: 0,
            background:
              'radial-gradient(circle at 50% 38%, rgba(6,182,212,0.33), transparent 34%), radial-gradient(circle at 20% 80%, rgba(16,185,129,0.18), transparent 30%)',
          }}
        />
        <div
          style={{
            width: 260,
            height: 260,
            borderRadius: 84,
            display: 'grid',
            placeItems: 'center',
            background: 'rgba(255,255,255,0.13)',
            border: '1px solid rgba(255,255,255,0.28)',
            fontSize: 124,
            transform: `scale(${pulse})`,
            position: 'relative',
          }}
        >
          {segment.icon}
        </div>
        <div style={{height: 56}} />
        {segment.bullets.map((bullet, index) => (
          <div
            key={bullet}
            style={{
              width: 650,
              marginTop: index === 0 ? 0 : 18,
              padding: '20px 28px',
              borderRadius: 26,
              background: 'rgba(255,255,255,0.13)',
              display: 'flex',
              gap: 18,
              alignItems: 'center',
              fontSize: 30,
              fontWeight: 700,
              opacity: interpolate(frame, [18 + index * 12, 34 + index * 12], [0, 1], {
                extrapolateLeft: 'clamp',
                extrapolateRight: 'clamp',
              }),
            }}
          >
            <span style={{color: '#67e8f9'}}>✓</span>
            {bullet}
          </div>
        ))}
      </div>
      <FeatureSubtitle>{segment.subtitle}</FeatureSubtitle>
    </AbsoluteFill>
  );
}

function FeatureHeader({eyebrow, title}: {eyebrow: string; title: string}) {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [0, 16], [0, 1], {extrapolateRight: 'clamp'});
  const y = interpolate(frame, [0, 18], [24, 0], {extrapolateRight: 'clamp'});

  return (
    <div style={{opacity, transform: `translateY(${y}px)`}}>
      <div
        style={{
          display: 'inline-flex',
          padding: '10px 18px',
          borderRadius: 999,
          color: colors.blue,
          background: 'rgba(37, 99, 235, 0.1)',
          fontSize: 24,
          fontWeight: 800,
          letterSpacing: 0.5,
          textTransform: 'uppercase',
        }}
      >
        {eyebrow}
      </div>
      <h2
        style={{
          margin: '22px 0 0',
          fontSize: 66,
          lineHeight: 1.02,
          letterSpacing: -2.4,
          color: colors.dark,
        }}
      >
        {title}
      </h2>
    </div>
  );
}

function FeatureSubtitle({children}: {children: React.ReactNode}) {
  return (
    <p
      style={{
        margin: '42px 0 0',
        color: colors.muted,
        fontSize: 31,
        lineHeight: 1.32,
        fontWeight: 560,
      }}
    >
      {children}
    </p>
  );
}

function VideoFeature({segment}: {segment: Extract<(typeof segments)[number], {kind: 'video'}>}) {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const enter = spring({frame, fps, config: {damping: 20, stiffness: 92}});
  const exitFade = interpolate(frame, [durationInFrames - 18, durationInFrames], [1, 0.88], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  return (
    <AbsoluteFill style={{padding: '102px 78px'}}>
      <FeatureHeader eyebrow={segment.eyebrow} title={segment.title} />
      <div
        style={{
          marginTop: 52,
          width: 840,
          height: 840,
          alignSelf: 'center',
          borderRadius: 72,
          padding: 18,
          background: 'linear-gradient(180deg, rgba(255,255,255,0.92), rgba(255,255,255,0.68))',
          boxShadow: '0 40px 120px rgba(15,23,42,0.18)',
          border: '1px solid rgba(15,23,42,0.06)',
          transform: `translateY(${interpolate(enter, [0, 1], [34, 0])}px) scale(${0.96 + enter * 0.04})`,
          opacity: exitFade,
        }}
      >
        <div
          style={{
            width: '100%',
            height: '100%',
            overflow: 'hidden',
            borderRadius: 56,
            background: '#0b1220',
            position: 'relative',
          }}
        >
          <OffthreadVideo
            src={staticFile(`clips/${segment.file}`)}
            muted
            style={{
              width: '100%',
              height: '100%',
              objectFit: 'cover',
              display: 'block',
            }}
          />
          <div
            style={{
              position: 'absolute',
              inset: 0,
              boxShadow: 'inset 0 0 0 1px rgba(255,255,255,0.16)',
              borderRadius: 56,
              pointerEvents: 'none',
            }}
          />
        </div>
      </div>
      <FeatureSubtitle>{segment.subtitle}</FeatureSubtitle>
    </AbsoluteFill>
  );
}

function TimelineBar() {
  const frame = useCurrentFrame();
  const progress = interpolate(frame, [0, totalFrames], [0, 1], {extrapolateRight: 'clamp'});
  return (
    <div
      style={{
        position: 'absolute',
        left: 78,
        right: 78,
        bottom: 58,
        height: 7,
        borderRadius: 99,
        background: 'rgba(15, 23, 42, 0.09)',
        overflow: 'hidden',
      }}
    >
      <div
        style={{
          width: `${progress * 100}%`,
          height: '100%',
          background: 'linear-gradient(90deg, #2563eb, #06b6d4, #10b981)',
          borderRadius: 99,
        }}
      />
    </div>
  );
}

function Footer() {
  return (
    <div
      style={{
        position: 'absolute',
        left: 78,
        right: 78,
        bottom: 82,
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        color: 'rgba(15,23,42,0.45)',
        fontSize: 22,
        fontWeight: 700,
        letterSpacing: 0.2,
      }}
    >
      <span>Local-first capture for Obsidian & Markdown</span>
      <span>vox.isolated.tech</span>
    </div>
  );
}

function Outro() {
  const frame = useCurrentFrame();
  const scale = spring({frame, fps, config: {damping: 16, stiffness: 90}});

  return (
    <AbsoluteFill style={{padding: '120px 78px', justifyContent: 'center'}}>
      <div style={{transform: `scale(${scale})`}}>
        <BrandMark />
        <h1
          style={{
            margin: '72px 0 22px',
            fontSize: 92,
            lineHeight: 0.96,
            letterSpacing: -4.6,
            color: colors.dark,
          }}
        >
          Capture before the thought disappears.
        </h1>
        <p style={{fontSize: 36, lineHeight: 1.28, color: colors.muted, fontWeight: 560, margin: 0}}>
          Vox.md 2.8 is available now on the App Store.
        </p>
      </div>
    </AbsoluteFill>
  );
}

export function ReleaseVideo() {
  let cursor = introFrames;
  return (
    <AbsoluteFill style={{fontFamily: 'Inter, SF Pro Display, -apple-system, BlinkMacSystemFont, sans-serif'}}>
      <GradientBackground />
      <Sequence durationInFrames={introFrames}>
        <Intro />
      </Sequence>
      {segments.map((segment, index) => {
        const from = cursor;
        cursor += segment.duration;
        return (
          <Sequence key={index} from={from} durationInFrames={segment.duration}>
            {segment.kind === 'video' ? <VideoFeature segment={segment} /> : <TextFeature segment={segment} />}
          </Sequence>
        );
      })}
      <Sequence from={cursor} durationInFrames={outroFrames}>
        <Outro />
      </Sequence>
      <Footer />
      <TimelineBar />
    </AbsoluteFill>
  );
}

function Root() {
  return (
    <Composition
      id="ReleaseVideo"
      component={ReleaseVideo}
      durationInFrames={totalFrames}
      fps={fps}
      width={1080}
      height={1920}
      defaultProps={{}}
    />
  );
}

registerRoot(Root);
