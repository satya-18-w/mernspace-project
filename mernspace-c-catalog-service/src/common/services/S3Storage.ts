import {
    DeleteObjectCommand,
    GetObjectCommand,
    PutObjectCommand,
    S3Client,
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import config from "config";
import { FileData, FileStorage } from "../types/storage";
import createHttpError from "http-errors";

export class S3Storage implements FileStorage {
    private client: S3Client;

    constructor() {
        // When accessKeyId/secretAccessKey are absent, fall back to the SDK's
        // default credential chain (EC2 instance role / IRSA), so no static
        // AWS keys need to live in pod config.
        const credentials = config.has("s3.accessKeyId")
            ? {
                  accessKeyId: config.get<string>("s3.accessKeyId"),
                  secretAccessKey: config.get<string>("s3.secretAccessKey"),
              }
            : undefined;

        this.client = new S3Client({
            region: config.get<string>("s3.region"),
            ...(credentials ? { credentials } : {}),
        });
    }
    async upload(data: FileData): Promise<void> {
        const objectParams = {
            Bucket: config.get<string>("s3.bucket"),
            Key: data.filename,
            Body: data.fileData,
        };

        // todo: add proper filedata type
        // eslint-disable-next-line @typescript-eslint/ban-ts-comment
        // @ts-ignore
        return await this.client.send(new PutObjectCommand(objectParams));
    }

    async delete(filename: string): Promise<void> {
        const objectParams = {
            Bucket: config.get<string>("s3.bucket"),
            Key: filename,
        };

        // todo: add proper filedata type
        // eslint-disable-next-line @typescript-eslint/ban-ts-comment
        // @ts-ignore
        return await this.client.send(new DeleteObjectCommand(objectParams));
    }
    async getObjectUri(filename: string): Promise<string> {
        const bucket = config.get<string>("s3.bucket");
        const region = config.get<string>("s3.region");

        if (typeof bucket !== "string" || typeof region !== "string") {
            throw createHttpError(500, "Invalid S3 configuration");
        }

        // The bucket stays private (Block Public Access on); each response gets
        // a short-lived signed URL instead of a public object URL.
        const expiresIn = config.has("s3.urlExpirySeconds")
            ? config.get<number>("s3.urlExpirySeconds")
            : 86400;

        return getSignedUrl(
            this.client,
            new GetObjectCommand({ Bucket: bucket, Key: filename }),
            { expiresIn },
        );
    }
}
