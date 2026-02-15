import { useState, useEffect, useRef } from "react";

export function useVideoPlayback() {
  const [videoTime, setVideoTime] = useState(0);
  const [smoothVideoTime, setSmoothVideoTime] = useState(0);
  const [isVideoPlaying, setIsVideoPlaying] = useState(false);
  const videoRef = useRef<any>(null);
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const animationFrameRef = useRef<number | null>(null);

  const handleVideoTimeUpdate = (e: any) => {
    const currentTime = e?.detail?.currentTime ?? videoRef.current?.currentTime ?? 0;
    if (currentTime > 0) {
      setVideoTime(currentTime);
      // Only update smoothVideoTime when not playing (let animation frame handle it when playing)
      if (!isVideoPlaying) {
        setSmoothVideoTime(currentTime);
      }
    }
  };

  useEffect(() => {
    if (!isVideoPlaying) {
      if (animationFrameRef.current) {
        cancelAnimationFrame(animationFrameRef.current);
        animationFrameRef.current = null;
      }
      return;
    }

    const animate = () => {
      if (videoRef.current?.currentTime) {
        setSmoothVideoTime(videoRef.current.currentTime);
      }
      animationFrameRef.current = requestAnimationFrame(animate);
    };

    animationFrameRef.current = requestAnimationFrame(animate);

    return () => {
      if (animationFrameRef.current) {
        cancelAnimationFrame(animationFrameRef.current);
        animationFrameRef.current = null;
      }
    };
  }, [isVideoPlaying]);

  const handleVideoPlay = (alignmentData: any) => {
    setIsVideoPlaying(true);
    
    if (alignmentData && audioRef.current && videoRef.current) {
      const { videoTime: videoStartTime, mp3Time: mp3StartTime } = alignmentData;
      const audioDuration = audioRef.current.duration || 0;
      
      const syncAudio = () => {
        const mp3StartSeconds = mp3StartTime * audioRef.current!.duration;
        const currentVideoTime = videoRef.current?.currentTime || 0;
        const videoOffset = currentVideoTime - videoStartTime;
        const targetMp3Time = mp3StartSeconds + videoOffset;
        audioRef.current!.currentTime = Math.max(0, Math.min(targetMp3Time, audioRef.current!.duration));
        audioRef.current!.play().catch((err) => {
          console.error("Error playing MP3:", err);
        });
      };

      if (audioDuration === 0) {
        audioRef.current.addEventListener("loadedmetadata", syncAudio, { once: true });
      } else {
        syncAudio();
      }
    }
  };

  const handleVideoPause = () => {
    setIsVideoPlaying(false);
    audioRef.current?.pause();
  };

  const handleVideoSeek = (alignmentData: any) => {
    if (videoRef.current?.currentTime) {
      setSmoothVideoTime(videoRef.current.currentTime);
    }
    
    if (alignmentData && audioRef.current && videoRef.current) {
      const { videoTime: videoStartTime, mp3Time: mp3StartTime } = alignmentData;
      const audioDuration = audioRef.current.duration;
      
      if (audioDuration > 0) {
        const mp3StartSeconds = mp3StartTime * audioDuration;
        const currentVideoTime = videoRef.current.currentTime || 0;
        const videoOffset = currentVideoTime - videoStartTime;
        const targetMp3Time = mp3StartSeconds + videoOffset;
        audioRef.current.currentTime = Math.max(0, Math.min(targetMp3Time, audioDuration));
      }
    }
  };

  return {
    videoTime,
    smoothVideoTime,
    isVideoPlaying,
    videoRef,
    audioRef,
    handleVideoTimeUpdate,
    handleVideoPlay,
    handleVideoPause,
    handleVideoSeek,
  };
}

