// SPDX-License-Identifier: MIT
// ABI re-export typed as a const so viem infers argument types.
import glyphAbiJson from "../abi/GlyphRegistry.json";
import type { Abi } from "viem";

export const glyphAbi = glyphAbiJson as Abi;
