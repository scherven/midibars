import MIDIPlayer from "@/app/components/FileUploadAreas";
import VideoPlayer from "@/app/components/VideoPlayer";
import EditPageClient from "./EditPageClient";
import { Mux } from "@mux/mux-node";

const client = new Mux({
  tokenId: process.env["MUX_TOKEN_ID"],
  tokenSecret: process.env["MUX_TOKEN_SECRET"],
});

export default async function WatchPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const asset = await client.video.assets.retrieve(id);

  return (
    <EditPageClient id={id} playbackId={asset.playback_ids?.[0]?.id || null}>
      <div style={{ maxWidth: "1200px", margin: "0 auto", padding: "20px" }}>
        <MIDIPlayer id={id} />

        {asset.playback_ids?.[0]?.id ? (
          <VideoPlayer playbackId={asset.playback_ids[0].id} />
        ) : (
          <div
            style={{
              padding: "40px",
              textAlign: "center",
              border: "1px solid #ddd",
              borderRadius: "8px",
            }}
          >
            <p>Video is still processing. Please check back in a moment.</p>
          </div>
        )}
      </div>
    </EditPageClient>
  );
}
