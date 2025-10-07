#!/usr/bin/env node
import { exitOnValidationResult, validateCatalogFromFiles } from "./catalogValidator";

const result = validateCatalogFromFiles();
exitOnValidationResult(result);
