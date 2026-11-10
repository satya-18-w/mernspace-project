export interface FileData {
    filename: string;
    fileData: Buffer;
}

export interface FileStorage {
    upload(data: FileData): Promise<void>;
    delete(filename: string): Promise<void>;
    getObjectUri(filename: string): Promise<string>;
}
