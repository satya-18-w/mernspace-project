import "reflect-metadata";
import { DataSource } from "typeorm";
import { Config } from ".";

const useSsl =
    process.env.DB_SSL === "true" ||
    process.env.PGSSLMODE === "require" ||
    (!["localhost", "127.0.0.1", "postgres"].includes(Config.DB_HOST || "") &&
        !Config.DB_HOST?.startsWith("127."));

export const AppDataSource = new DataSource({
    type: "postgres",
    host: Config.DB_HOST,
    port: Number(Config.DB_PORT),
    username: Config.DB_USERNAME,
    password: Config.DB_PASSWORD,
    database: Config.DB_NAME,
    ssl: useSsl ? { rejectUnauthorized: false } : false,
    // Don't use this in production. Always keep false
    synchronize: false,
    logging: false,
    entities: ["src/entity/*.{ts,js}"],
    migrations: ["src/migration/*.{ts,js}"],
    subscribers: [],
});
