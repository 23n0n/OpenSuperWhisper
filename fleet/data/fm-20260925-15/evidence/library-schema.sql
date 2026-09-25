CREATE TABLE "recordings" ("id" TEXT PRIMARY KEY, "timestamp" DATETIME NOT NULL, "fileName" TEXT NOT NULL, "transcription" TEXT NOT NULL COLLATE NOCASE, "duration" DOUBLE NOT NULL, "status" TEXT NOT NULL DEFAULT 'completed', "progress" DOUBLE NOT NULL DEFAULT 1.0, "sourceFileURL" TEXT);
CREATE INDEX "recordings_on_timestamp" ON "recordings"("timestamp");
CREATE INDEX "recordings_on_transcription" ON "recordings"("transcription");
