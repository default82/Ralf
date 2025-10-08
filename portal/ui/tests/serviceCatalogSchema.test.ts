import { describe, expect, it } from "vitest";
import Ajv from "ajv";
import addFormats from "ajv-formats";
import schemaJson from "../../api/schema/service_catalog.schema.json";
import {
  ServiceCatalog,
  readCatalog,
  validateCatalog,
  readSchema
} from "../lib/catalogValidator";

describe("service catalog schema", () => {
  const schema = schemaJson ?? readSchema();
  const buildAjv = () => {
    const ajv = new Ajv({ allErrors: true, useDefaults: true, coerceTypes: true });
    addFormats(ajv);
    return ajv;
  };

  it("accepts the provided example catalog", () => {
    const catalog = readCatalog();
    const result = validateCatalog(catalog, schema);
    expect(result.valid).toBe(true);
    expect(result.errors).toHaveLength(0);
    expect(result.catalog?.length).toBeGreaterThanOrEqual(1);
  });

  it("rejects ids that are not lowercase kebab-case", () => {
    const invalidCatalog: ServiceCatalog = [
      {
        id: "Payments_API",
        name: "Payments API",
        summary: "Handles payments.",
        owner: "Payments Team",
        tier: "mission-critical",
        status: "operational",
        tags: [],
        links: []
      }
    ];

    const ajv = buildAjv();
    const validate = ajv.compile<ServiceCatalog>(schema);
    const valid = validate(invalidCatalog);

    expect(valid).toBe(false);
    expect(validate.errors?.some((error) => error.instancePath === "/0/id")).toBe(
      true
    );
  });

  it("applies defaults for optional arrays", () => {
    const catalogWithoutOptional: unknown = [
      {
        id: "feature-flags",
        name: "Feature Flags",
        summary: "Allows gradual roll-out and experimentation.",
        owner: "Platform Squad",
        tier: "internal",
        status: "operational"
      }
    ];

    const ajv = buildAjv();
    const validate = ajv.compile<ServiceCatalog>(schema);
    const valid = validate(catalogWithoutOptional);

    expect(valid).toBe(true);
    const [service] = catalogWithoutOptional as ServiceCatalog;
    expect(service.tags).toEqual([]);
    expect(service.links).toEqual([]);
  });
});
