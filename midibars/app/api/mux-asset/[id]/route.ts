import { NextResponse } from "next/server";
import { Mux } from "@mux/mux-node";

const client = new Mux({
  tokenId: process.env["MUX_TOKEN_ID"],
  tokenSecret: process.env["MUX_TOKEN_SECRET"],
});

export async function GET(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  try {
    const { id } = await params;
    const asset = await client.video.assets.retrieve(id);
    return NextResponse.json(asset);
  } catch (error) {
    console.error("Error fetching Mux asset:", error);
    return NextResponse.json(
      { error: "Failed to fetch asset" },
      { status: 500 },
    );
  }
}

