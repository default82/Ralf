import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import Ajv, { DefinedError, ValidateFunction } from "ajv";
import addFormats from "ajv-formats";
import { load as loadYaml } from "js-yaml";

export interface ServiceLink {
  title: string;
  url: string;
  category?: string;
}

export type ServiceTier =
  | "mission-critical"
  | "business-critical"
  | "internal"
  | "experimental";

export type ServiceStatus =
  | "operational"
  | "degraded"
  | "maintenance"
  | "outage";

export interface ServiceEntry {
  id: string;
  name: string;
  summary: string;
  owner: string;
  tier: ServiceTier;
  status: ServiceStatus;
  tags: string[];
  links: ServiceLink[];
}

export type ServiceCatalog = ServiceEntry[];

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export const DEFAULT_SCHEMA_PATH = path.resolve(
  __dirname,
  "..",
  "..",
  "api",
  "schema",
  "service_catalog.schema.json"
);

export const DEFAULT_CATALOG_PATH = path.resolve(
  __dirname,
  "..",
  "data",
  "services.yaml"
);

function loadFile(filePath: string): string {
  return fs.readFileSync(filePath, "utf-8");
}

export function readSchema(schemaPath: string = DEFAULT_SCHEMA_PATH): unknown {
  const rawSchema = loadFile(schemaPath);
  return JSON.parse(rawSchema);
}

export function readCatalog(catalogPath: string = DEFAULT_CATALOG_PATH): unknown {
  const rawCatalog = loadFile(catalogPath);
  return loadYaml(rawCatalog);
}

function buildValidator(schema: unknown): ValidateFunction<ServiceCatalog> {
  const ajv = new Ajv({
    allErrors: true,
    useDefaults: true,
    coerceTypes: true
  });
  addFormats(ajv);
  return ajv.compile<ServiceCatalog>(schema);
}

function collectAjvErrors(errors: DefinedError[] | null | undefined): string[] {
  if (!errors) {
    return [];
  }

  return errors.map((error) => {
    const instancePath = error.instancePath || "/";
    return `${instancePath} ${error.message ?? "failed validation"}`.trim();
  });
}

function findDuplicateIds(catalog: ServiceCatalog): string[] {
  const seen = new Map<string, number>();
  for (const service of catalog) {
    const count = seen.get(service.id) ?? 0;
    seen.set(service.id, count + 1);
  }

  return Array.from(seen.entries())
    .filter(([, count]) => count > 1)
    .map(([id]) => id);
}

export interface CatalogValidationResult {
  valid: boolean;
  errors: string[];
  catalog?: ServiceCatalog;
}

export function validateCatalog(
  catalogInput: unknown,
  schemaInput: unknown = readSchema()
): CatalogValidationResult {
  const validator = buildValidator(schemaInput);
  const valid = validator(catalogInput);

  if (!valid) {
    return {
      valid: false,
      errors: collectAjvErrors(validator.errors)
    };
  }

  const catalog = catalogInput as ServiceCatalog;
  const duplicates = findDuplicateIds(catalog);
  if (duplicates.length > 0) {
    return {
      valid: false,
      errors: duplicates.map(
        (dup) => `Duplicate service id detected: "${dup}"`
      )
    };
  }

  return {
    valid: true,
    errors: [],
    catalog
  };
}

export function validateCatalogFromFiles(
  catalogPath: string = DEFAULT_CATALOG_PATH,
  schemaPath: string = DEFAULT_SCHEMA_PATH
): CatalogValidationResult {
  try {
    const catalog = readCatalog(catalogPath);
    const schema = readSchema(schemaPath);
    return validateCatalog(catalog, schema);
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Unknown validation error";
    return { valid: false, errors: [message] };
  }
}

export function exitOnValidationResult(result: CatalogValidationResult): void {
  if (!result.valid) {
    for (const error of result.errors) {
      console.error(`\u274c ${error}`);
    }
    process.exitCode = 1;
    return;
  }

  console.log(
    `\u2705 Service catalog is valid (${result.catalog?.length ?? 0} entries).`
  );
}
