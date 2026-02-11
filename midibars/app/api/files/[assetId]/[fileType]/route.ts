import { NextRequest, NextResponse } from "next/server";
import { readFile } from "fs/promises";
import { join } from "path";
import { existsSync } from "fs";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ assetId: string; fileType: string }> }
) {
  try {
    const { assetId, fileType } = await params;

    // Find the file in the uploads directory
    const uploadsDir = join(process.cwd(), "uploads", assetId);
    
    // Check if directory exists
    if (!existsSync(uploadsDir)) {
      return NextResponse.json(
        { error: "File not found" },
        { status: 404 }
      );
    }

    const fs = await import("fs/promises");
    const files = await fs.readdir(uploadsDir).catch(() => []);

    // Find file that starts with the fileType
    const fileName = files.find((f) => f.startsWith(`${fileType}-`));
    if (!fileName) {
      return NextResponse.json(
        { error: "File not found" },
        { status: 404 }
      );
    }

    const filePath = join(uploadsDir, fileName);
    if (!existsSync(filePath)) {
      return NextResponse.json(
        { error: "File not found" },
        { status: 404 }
      );
    }

    const fileBuffer = await readFile(filePath);
    const mimeType =
      fileType === "mp3"
        ? "audio/mpeg"
        : fileType === "midi"
          ? "audio/midi"
          : "application/octet-stream";

    return new NextResponse(fileBuffer, {
      headers: {
        "Content-Type": mimeType,
        "Content-Disposition": `attachment; filename="${fileName}"`,
      },
    });
  } catch (error) {
    console.error("Error serving file:", error);
    return NextResponse.json(
      { error: "Failed to serve file" },
      { status: 500 }
    );
  }
}

