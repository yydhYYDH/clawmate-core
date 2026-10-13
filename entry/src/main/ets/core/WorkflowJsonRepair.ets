interface JsonRepairContext {
  kind: string;
  state: string;
}

interface BareCoordinateFieldSpec {
  key: string;
  count: number;
}

interface BareCoordinateParseResult {
  values: string[];
  endIndex: number;
}

export class WorkflowJsonRepair {
  static normalizeJsonText(raw: string): string {
    let text = raw.trim();
    let block = text.match(/```(?:json)?\s*([\s\S]*?)\s*```/i);
    if (block && block.length > 1) {
      text = block[1].trim();
    }
    text = text.replace(/^```(?:json)?\s*/i, '');
    text = text.replace(/\s*```$/, '');
    text = WorkflowJsonRepair.repairLeadingReasoningFragment(text.trim());
    text = WorkflowJsonRepair.repairMissingLeadingObjectBrace(text.trim());
    text = WorkflowJsonRepair.extractFirstJsonObjectText(text);
    text = WorkflowJsonRepair.repairMissingLeadingObjectBrace(text.trim());
    return WorkflowJsonRepair.repairLeadingBrokenObjectQuote(text.trim());
  }

  // 模型偶发省略 {"reasoning":" 前缀，只留下自然语言 + ","action":...。
  // 在提取首个花括号前补回完整对象，否则会误把 parameters 子对象当作顶层 JSON。
  private static repairLeadingReasoningFragment(text: string): string {
    let trimmed = text.trim();
    if (trimmed.length === 0 || trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return trimmed;
    }
    let actionMarker = trimmed.search(/"\s*,\s*"action"\s*:/i);
    if (actionMarker <= 0) {
      return trimmed;
    }
    let reasoning = trimmed.substring(0, actionMarker).trim();
    if (reasoning.length === 0) {
      return trimmed;
    }
    return '{"reasoning":"' + WorkflowJsonRepair.escapeJsonStringContent(reasoning) +
      trimmed.substring(actionMarker);
  }

  private static escapeJsonStringContent(value: string): string {
    return value.replace(/\\/g, '\\\\')
      .replace(/"/g, '\\"')
      .replace(/\r/g, '\\r')
      .replace(/\n/g, '\\n')
      .replace(/\t/g, '\\t');
  }

  static repairCandidates(text: string): string[] {
    let candidates: string[] = [];
    let unwrapped = WorkflowJsonRepair.unwrapDuplicateOuterBraces(text);
    let leadingObjectBrace = WorkflowJsonRepair.repairMissingLeadingObjectBrace(text);
    let literalCase = WorkflowJsonRepair.repairJsonLiteralCasing(text);
    let unwrappedLiteralCase = WorkflowJsonRepair.repairJsonLiteralCasing(unwrapped);
    let numericArrayComma = WorkflowJsonRepair.repairNumberArrayCommas(text);
    let cjkPunctuation = WorkflowJsonRepair.normalizeCjkJsonPunctuation(text);
    let withoutParentheses = WorkflowJsonRepair.removeParentheses(text);
    let cjkPunctuationWithoutParentheses = WorkflowJsonRepair.removeParentheses(cjkPunctuation);
    let quotedKnownKeys = WorkflowJsonRepair.quoteKnownJsonKeys(text);
    let singleQuoted = WorkflowJsonRepair.repairSingleQuotedJson(text);
    let quotedArrayItems = WorkflowJsonRepair.quoteBareJsonArrayItems(text);
    let closed = WorkflowJsonRepair.closeTruncatedJson(text);
    let duplicateColons = WorkflowJsonRepair.repairDuplicateKeyColons(text);
    let cjkDuplicateColons = WorkflowJsonRepair.repairDuplicateKeyColons(cjkPunctuation);
    let bareCoordinateArrays = WorkflowJsonRepair.repairBareCoordinateArrays(text);
    let cjkBareCoordinateArrays = WorkflowJsonRepair.repairBareCoordinateArrays(cjkPunctuation);
    let duplicateColonBareCoordinateArrays = WorkflowJsonRepair.repairBareCoordinateArrays(duplicateColons);
    let nestedCoordinateArrays = WorkflowJsonRepair.repairNestedCoordinateArrays(text);
    let stringContent = WorkflowJsonRepair.repairJsonStringContent(text);
    let stringContentBareCoordinateArrays = WorkflowJsonRepair.repairBareCoordinateArrays(stringContent);
    WorkflowJsonRepair.addRepairCandidate(candidates, unwrapped, text);
    WorkflowJsonRepair.addRepairCandidate(candidates, leadingObjectBrace, text);
    WorkflowJsonRepair.addRepairCandidate(candidates, WorkflowJsonRepair.closeTruncatedJson(leadingObjectBrace), text);
    WorkflowJsonRepair.addRepairCandidate(candidates, literalCase, text);
    WorkflowJsonRepair.addRepairCandidate(candidates, unwrappedLiteralCase, text);
    WorkflowJsonRepair.addRepairCandidate(candidates, numericArrayComma, text);
    WorkflowJsonRepair.addRepairCandidate(candidates, bareCoordinateArrays, text);
    WorkflowJsonRepair.addRepairCandidate(candidates, WorkflowJsonRepair.closeTruncatedJson(bareCoordinateArrays), text);
    WorkflowJsonRepair.addRepairCandidate(candidates, cjkPunctuation, text);
    WorkflowJsonRepair.addRepairCandidate(candidates, WorkflowJsonRepair.closeTruncatedJson(cjkPunctuation), text);
    WorkflowJsonRepair.addRepairCandidate(candidates, withoutParentheses, text);
    WorkflowJsonRepair.addRepairCandidate(candidates, WorkflowJsonRepair.closeTruncatedJson(withoutParentheses), text);
    WorkflowJsonRepair.addRepairCandidate(candidates, cjkPunctuationWithoutParentheses, text);
    WorkflowJsonRepair.addRepairCandidate(candidates, WorkflowJsonRepair.closeTruncatedJson(cjkPunctuationWithoutParentheses), text);
    WorkflowJsonRepair.addRepairCandidate(candidates, quotedKnownKeys, text);
    WorkflowJsonRepair.addRepairCandidate(candidates, WorkflowJsonRepair.closeTruncatedJson(quotedKnownKeys), text);
    WorkflowJsonRepair.addRepairCandidate(candidates, singleQuoted, text);
    WorkflowJsonRepair.addRepairCandidate(candidates, WorkflowJsonRepair.closeTruncatedJson(singleQuoted), text);
    WorkflowJsonRepair.addRepairCandidate(candidates, quotedArrayItems, text);
    WorkflowJsonRepair.addRepairCandidate(candidates, WorkflowJsonRepair.quoteBareJsonArrayItems(cjkPunctuation), text);
    WorkflowJsonRepair.addRepairCandidate(candidates, duplicateColons, text);
    WorkflowJsonRepair.addRepairCandidate(candidates, cjkDuplicateColons, text);
    WorkflowJsonRepair.addRepairCandidate(candidates, duplicateColonBareCoordinateArrays, text);
    WorkflowJsonRepair.addRepairCandidate(candidates, WorkflowJsonRepair.closeTruncatedJson(duplicateColonBareCoordinateArrays), text);
    WorkflowJsonRepair.addRepairCandidate(candidates, nestedCoordinateArrays, text);
    WorkflowJsonRepair.addRepairCandidate(candidates, WorkflowJsonRepair.closeTruncatedJson(nestedCoordinateArrays), text);
    WorkflowJsonRepair.addRepairCandidate(candidates, WorkflowJsonRepair.repairNumberArrayCommas(unwrapped), text);
    WorkflowJsonRepair.addRepairCandidate(candidates, WorkflowJsonRepair.repairNumberArrayCommas(literalCase), text);
    WorkflowJsonRepair.addRepairCandidate(candidates, WorkflowJsonRepair.repairNumberArrayCommas(cjkPunctuation), text);
    WorkflowJsonRepair.addRepairCandidate(candidates, WorkflowJsonRepair.repairJsonLiteralCasing(cjkPunctuation), text);
    WorkflowJsonRepair.addRepairCandidate(candidates, cjkBareCoordinateArrays, text);
    WorkflowJsonRepair.addRepairCandidate(candidates, WorkflowJsonRepair.closeTruncatedJson(cjkBareCoordinateArrays), text);
    WorkflowJsonRepair.addRepairCandidate(candidates, closed, text);
    WorkflowJsonRepair.addRepairCandidate(candidates, WorkflowJsonRepair.closeTruncatedJson(literalCase), text);
    WorkflowJsonRepair.addRepairCandidate(candidates, WorkflowJsonRepair.repairBareCoordinateArrays(closed), text);
    WorkflowJsonRepair.addRepairCandidate(candidates, stringContent, text);
    WorkflowJsonRepair.addRepairCandidate(candidates, stringContentBareCoordinateArrays, text);
    WorkflowJsonRepair.addRepairCandidate(candidates, WorkflowJsonRepair.closeTruncatedJson(stringContentBareCoordinateArrays), text);
    WorkflowJsonRepair.addRepairCandidate(candidates, WorkflowJsonRepair.repairJsonStringContent(unwrapped), text);
    WorkflowJsonRepair.addRepairCandidate(candidates, WorkflowJsonRepair.repairJsonStringContent(literalCase), text);
    WorkflowJsonRepair.addRepairCandidate(candidates, WorkflowJsonRepair.repairJsonStringContent(cjkPunctuation), text);
    WorkflowJsonRepair.addRepairCandidate(candidates, WorkflowJsonRepair.repairJsonStringContent(withoutParentheses), text);
    WorkflowJsonRepair.addRepairCandidate(candidates, WorkflowJsonRepair.repairJsonStringContent(closed), text);
    WorkflowJsonRepair.addRepairCandidate(candidates,
      WorkflowJsonRepair.repairNestedCoordinateArrays(stringContent), text);
    return candidates;
  }

  private static extractFirstJsonObjectText(text: string): string {
    let start = text.indexOf('{');
    if (start < 0) {
      return text;
    }
    let depth = 0;
    let inString = false;
    let escaped = false;
    for (let i = start; i < text.length; i++) {
      let ch = text.charAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch === '\\') {
          escaped = true;
        } else if (ch === '"') {
          inString = false;
        }
        continue;
      }

      if (ch === '"') {
        inString = true;
      } else if (ch === '{') {
        depth++;
      } else if (ch === '}') {
        depth--;
        if (depth === 0) {
          return text.substring(start, i + 1);
        }
      }
    }

    let end = text.lastIndexOf('}');
    if (end > start) {
      return text.substring(start, end + 1);
    }
    return text.substring(start);
  }

  private static addRepairCandidate(candidates: string[], candidate: string, original: string): void {
    let normalized = candidate.trim();
    if (normalized.length === 0 || normalized === original.trim()) {
      return;
    }
    if (candidates.indexOf(normalized) < 0) {
      candidates.push(normalized);
    }
  }

  private static unwrapDuplicateOuterBraces(text: string): string {
    let trimmed = text.trim();
    if (trimmed.startsWith('{{') && trimmed.endsWith('}}')) {
      let inner = trimmed.substring(1, trimmed.length - 1).trim();
      if (inner.startsWith('{') && inner.endsWith('}')) {
        return inner;
      }
    }
    return trimmed;
  }

  private static repairNumberArrayCommas(text: string): string {
    return text.replace(/(\d+)\s+(\d+)/g, '$1, $2');
  }

  private static repairDuplicateKeyColons(text: string): string {
    return text.replace(/("[A-Za-z_][A-Za-z0-9_]*"\s*:)\s*:+/g, '$1');
  }

  private static repairNestedCoordinateArrays(text: string): string {
    let repaired = text.replace(/("bbox"\s*:\s*)\[\s*\[\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\]\s*\]?/g,
      '$1[$2,$3,$4,$5]');
    return repaired.replace(/("(?:coords|start_coords|end_coords)"\s*:\s*)\[\s*\[\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\]\s*\]?/g,
      '$1[$2,$3]');
  }

  private static repairBareCoordinateArrays(text: string): string {
    let specs: BareCoordinateFieldSpec[] = [
      { key: '"bbox"', count: 4 },
      { key: '"coords"', count: 2 },
      { key: '"start_coords"', count: 2 },
      { key: '"end_coords"', count: 2 }
    ];
    let repaired = text;
    for (let i = 0; i < specs.length; i++) {
      repaired = WorkflowJsonRepair.repairBareCoordinateField(repaired, specs[i]);
    }
    return repaired;
  }

  private static repairBareCoordinateField(text: string, spec: BareCoordinateFieldSpec): string {
    let result = '';
    let searchStart = 0;
    while (searchStart < text.length) {
      let keyIndex = text.indexOf(spec.key, searchStart);
      if (keyIndex < 0) {
        result += text.substring(searchStart);
        break;
      }

      let colonIndex = WorkflowJsonRepair.nextNonWhitespaceIndex(text, keyIndex + spec.key.length);
      let valueStart = colonIndex >= 0 && text.charAt(colonIndex) === ':' ?
        WorkflowJsonRepair.nextNonWhitespaceIndex(text, colonIndex + 1) : -1;
      if (valueStart < 0 || WorkflowJsonRepair.isStructuredJsonValueStart(text.charAt(valueStart))) {
        result += text.substring(searchStart, keyIndex + spec.key.length);
        searchStart = keyIndex + spec.key.length;
        continue;
      }

      let parsed = WorkflowJsonRepair.parseBareCoordinateValues(text, valueStart, spec.count);
      if (parsed === null) {
        result += text.substring(searchStart, keyIndex + spec.key.length);
        searchStart = keyIndex + spec.key.length;
        continue;
      }

      // 模型偶发输出 "bbox":100,200,300,400 这类非法 JSON，修复为数组后再交给 JSON.parse。
      result += text.substring(searchStart, valueStart);
      result += '[' + parsed.values.join(', ') + ']';
      searchStart = parsed.endIndex;
    }
    return result;
  }

  private static parseBareCoordinateValues(text: string, start: number, count: number): BareCoordinateParseResult | null {
    let values: string[] = [];
    let index = start;
    for (let i = 0; i < count; i++) {
      index = WorkflowJsonRepair.nextNonWhitespaceIndex(text, index);
      if (index < 0) {
        return null;
      }
      let numberEnd = WorkflowJsonRepair.readJsonNumberEnd(text, index);
      if (numberEnd <= index) {
        return null;
      }
      values.push(text.substring(index, numberEnd));
      let nextIndex = WorkflowJsonRepair.nextNonWhitespaceIndex(text, numberEnd);
      if (i < count - 1) {
        if (nextIndex < 0 || text.charAt(nextIndex) !== ',') {
          return null;
        }
        index = nextIndex + 1;
      } else {
        index = nextIndex >= 0 ? nextIndex : text.length;
      }
    }

    let boundaryIndex = WorkflowJsonRepair.nextNonWhitespaceIndex(text, index);
    let endIndex = index;
    if (boundaryIndex >= 0 && !WorkflowJsonRepair.isCoordinateBoundary(text.charAt(boundaryIndex))) {
      return null;
    }
    if (boundaryIndex >= 0 && text.charAt(boundaryIndex) === ']') {
      endIndex = boundaryIndex + 1;
    }
    return { values: values, endIndex: endIndex };
  }

  private static readJsonNumberEnd(text: string, start: number): number {
    let index = start;
    if (index < text.length && text.charAt(index) === '-') {
      index++;
    }
    let integerStart = index;
    while (index < text.length && WorkflowJsonRepair.isAsciiDigit(text.charAt(index))) {
      index++;
    }
    if (index === integerStart) {
      return -1;
    }
    if (index < text.length && text.charAt(index) === '.') {
      index++;
      let decimalStart = index;
      while (index < text.length && WorkflowJsonRepair.isAsciiDigit(text.charAt(index))) {
        index++;
      }
      if (index === decimalStart) {
        return -1;
      }
    }
    if (index < text.length && (text.charAt(index) === 'e' || text.charAt(index) === 'E')) {
      let exponentStart = index;
      index++;
      if (index < text.length && (text.charAt(index) === '+' || text.charAt(index) === '-')) {
        index++;
      }
      let digitStart = index;
      while (index < text.length && WorkflowJsonRepair.isAsciiDigit(text.charAt(index))) {
        index++;
      }
      if (index === digitStart) {
        return exponentStart;
      }
    }
    return index;
  }

  private static isStructuredJsonValueStart(ch: string): boolean {
    return ch === '[' || ch === '{' || ch === '"';
  }

  private static isCoordinateBoundary(ch: string): boolean {
    return ch === ',' || ch === '}' || ch === ']';
  }

  private static normalizeCjkJsonPunctuation(text: string): string {
    return text.replace(/[“”]/g, '"')
      .replace(/[‘’]/g, "'")
      .replace(/，/g, ',')
      .replace(/：/g, ':');
  }

  private static removeParentheses(text: string): string {
    return text.replace(/[()（）]/g, '');
  }

  private static quoteKnownJsonKeys(text: string): string {
    return text.replace(/([{,]\s*)(title|category|summary|details|tags|importance)\s*:/g, '$1"$2":');
  }

  private static repairSingleQuotedJson(text: string): string {
    return text.replace(/'([^'\\]*(?:\\.[^'\\]*)*)'/g, '"$1"');
  }

  private static quoteBareJsonArrayItems(text: string): string {
    return text.replace(/\[([^\[\]{}"]*)\]/g, (match: string, body: string): string => {
      if (body.indexOf(':') >= 0) {
        return match;
      }
      let parts = body.split(/[,，、;；]/);
      let quoted: string[] = [];
      for (let i = 0; i < parts.length; i++) {
        let value = parts[i].trim();
        if (value.length === 0) {
          continue;
        }
        if (value === 'true' || value === 'false' || value === 'null' || !isNaN(Number(value))) {
          quoted.push(value);
        } else {
          quoted.push('"' + value.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"');
        }
      }
      return '[' + quoted.join(',') + ']';
    });
  }

  private static repairJsonLiteralCasing(text: string): string {
    let result = '';
    let inString = false;
    let escaped = false;
    for (let i = 0; i < text.length; i++) {
      let ch = text.charAt(i);
      if (inString) {
        result += ch;
        if (escaped) {
          escaped = false;
        } else if (ch === '\\') {
          escaped = true;
        } else if (ch === '"') {
          inString = false;
        }
        continue;
      }

      if (ch === '"') {
        inString = true;
        result += ch;
        continue;
      }

      if (WorkflowJsonRepair.isAsciiLetter(ch)) {
        let start = i;
        while (i < text.length && WorkflowJsonRepair.isAsciiLetter(text.charAt(i))) {
          i++;
        }
        let word = text.substring(start, i);
        let lowered = word.toLowerCase();
        if (lowered === 'true' || lowered === 'false' || lowered === 'null') {
          result += lowered;
        } else if (lowered === 'none') {
          result += 'null';
        } else {
          result += word;
        }
        i--;
        continue;
      }

      result += ch;
    }
    return result;
  }

  private static closeTruncatedJson(text: string): string {
    let trimmed = text.trim();
    if (trimmed.length === 0 || (trimmed.charAt(0) !== '{' && trimmed.charAt(0) !== '[')) {
      return trimmed;
    }

    let stack: string[] = [];
    let inString = false;
    let escaped = false;
    for (let i = 0; i < trimmed.length; i++) {
      let ch = trimmed.charAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch === '\\') {
          escaped = true;
        } else if (ch === '"') {
          inString = false;
        }
        continue;
      }

      if (ch === '"') {
        inString = true;
      } else if (ch === '{') {
        stack.push('}');
      } else if (ch === '[') {
        stack.push(']');
      } else if (ch === '}' || ch === ']') {
        if (stack.length === 0 || stack[stack.length - 1] !== ch) {
          return trimmed;
        }
        stack.pop();
      }
    }

    if (trimmed.endsWith(':')) {
      return trimmed;
    }
    let repaired = trimmed;
    if (repaired.endsWith(',')) {
      repaired = repaired.substring(0, repaired.length - 1).trim();
    }
    if (inString) {
      if (escaped) {
        repaired += '\\';
      }
      repaired += '"';
    }
    while (stack.length > 0) {
      repaired = repaired.replace(/,\s*$/, '');
      let closer = stack.pop();
      if (closer !== undefined) {
        repaired += closer;
      }
    }
    return repaired;
  }

  private static repairJsonStringContent(text: string): string {
    let result = '';
    let inString = false;
    let escaped = false;
    let stringRole = '';
    let contexts: JsonRepairContext[] = [];
    for (let i = 0; i < text.length; i++) {
      let ch = text.charAt(i);
      if (!inString) {
        if (ch === '"') {
          inString = true;
          escaped = false;
          stringRole = WorkflowJsonRepair.jsonStringRole(contexts);
        } else {
          WorkflowJsonRepair.updateContext(contexts, ch);
        }
        result += ch;
        continue;
      }

      if (escaped) {
        result += ch;
        escaped = false;
        continue;
      }

      if (ch === '\\') {
        result += ch;
        escaped = true;
        continue;
      }

      if (ch === '"') {
        if (WorkflowJsonRepair.isJsonStringCloseAt(text, i, stringRole, contexts)) {
          inString = false;
          WorkflowJsonRepair.finishString(contexts, stringRole);
          stringRole = '';
          result += ch;
        } else {
          result += '\\"';
        }
        continue;
      }

      if (ch === '\n') {
        result += '\\n';
        continue;
      }
      if (ch === '\r') {
        continue;
      }
      if (ch === '\t') {
        result += '\\t';
        continue;
      }
      result += ch;
    }
    return result;
  }

  private static updateContext(contexts: JsonRepairContext[], ch: string): void {
    if (ch === '{') {
      contexts.push({ kind: 'object', state: 'keyOrEnd' });
      return;
    }
    if (ch === '[') {
      contexts.push({ kind: 'array', state: 'valueOrEnd' });
      return;
    }
    if (ch === '}' || ch === ']') {
      if (contexts.length > 0) {
        contexts.pop();
      }
      WorkflowJsonRepair.markValueFinished(contexts);
      return;
    }
    let top = WorkflowJsonRepair.peekContext(contexts);
    if (top === null) {
      return;
    }
    if (ch === ':' && top.kind === 'object') {
      top.state = 'value';
    } else if (ch === ',') {
      top.state = top.kind === 'object' ? 'keyOrEnd' : 'valueOrEnd';
    }
  }

  private static jsonStringRole(contexts: JsonRepairContext[]): string {
    let top = WorkflowJsonRepair.peekContext(contexts);
    if (top !== null && top.kind === 'object' && top.state === 'keyOrEnd') {
      return 'key';
    }
    return 'value';
  }

  private static finishString(contexts: JsonRepairContext[], role: string): void {
    let top = WorkflowJsonRepair.peekContext(contexts);
    if (role === 'key' && top !== null && top.kind === 'object') {
      top.state = 'colon';
      return;
    }
    WorkflowJsonRepair.markValueFinished(contexts);
  }

  private static markValueFinished(contexts: JsonRepairContext[]): void {
    let top = WorkflowJsonRepair.peekContext(contexts);
    if (top !== null) {
      top.state = 'commaOrEnd';
    }
  }

  private static peekContext(contexts: JsonRepairContext[]): JsonRepairContext | null {
    if (contexts.length === 0) {
      return null;
    }
    return contexts[contexts.length - 1];
  }

  private static isJsonStringCloseAt(text: string, quoteIndex: number, role: string,
    contexts: JsonRepairContext[]): boolean {
    let nextIndex = WorkflowJsonRepair.nextNonWhitespaceIndex(text, quoteIndex + 1);
    let next = nextIndex >= 0 ? text.charAt(nextIndex) : '';
    if (role === 'key') {
      return next === ':';
    }
    if (next.length === 0 || next === '}' || next === ']') {
      return true;
    }
    if (next !== ',') {
      return false;
    }
    let top = WorkflowJsonRepair.peekContext(contexts);
    if (top === null || top.kind === 'array') {
      return true;
    }
    return WorkflowJsonRepair.commaStartsNextObjectField(text, nextIndex);
  }

  private static commaStartsNextObjectField(text: string, commaIndex: number): boolean {
    let keyStart = WorkflowJsonRepair.nextNonWhitespaceIndex(text, commaIndex + 1);
    if (keyStart < 0 || text.charAt(keyStart) !== '"') {
      return false;
    }
    let keyEnd = WorkflowJsonRepair.findNextUnescapedQuote(text, keyStart + 1);
    if (keyEnd < 0) {
      return false;
    }
    let afterKey = WorkflowJsonRepair.nextNonWhitespaceIndex(text, keyEnd + 1);
    return afterKey >= 0 && text.charAt(afterKey) === ':';
  }

  private static findNextUnescapedQuote(text: string, start: number): number {
    let escaped = false;
    for (let i = start; i < text.length; i++) {
      let ch = text.charAt(i);
      if (escaped) {
        escaped = false;
      } else if (ch === '\\') {
        escaped = true;
      } else if (ch === '"') {
        return i;
      }
    }
    return -1;
  }

  private static nextNonWhitespaceIndex(text: string, start: number): number {
    for (let i = start; i < text.length; i++) {
      let ch = text.charAt(i);
      if (ch !== ' ' && ch !== '\n' && ch !== '\r' && ch !== '\t') {
        return i;
      }
    }
    return -1;
  }

  private static isAsciiLetter(ch: string): boolean {
    return (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z');
  }

  private static isAsciiDigit(ch: string): boolean {
    return ch >= '0' && ch <= '9';
  }

  private static repairMissingLeadingObjectBrace(text: string): string {
    let trimmed = text.trim();
    if (trimmed.length === 0 || trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return trimmed;
    }
    if (WorkflowJsonRepair.startsWithKnownTopLevelKeyMissingOpenQuote(trimmed)) {
      return WorkflowJsonRepair.closeTruncatedJson('{"' + trimmed);
    }
    if (!WorkflowJsonRepair.startsWithKnownTopLevelKey(trimmed)) {
      return trimmed;
    }
    return WorkflowJsonRepair.closeTruncatedJson('{' + trimmed);
  }

  private static startsWithKnownTopLevelKey(text: string): boolean {
    return /^"(action|parameters|reasoning|reason|app|app_name|package_name|target_app|bundle|bundle_name|task_description|template_name|title|category|summary|details|tags|importance)"\s*:/.test(text);
  }

  private static startsWithKnownTopLevelKeyMissingOpenQuote(text: string): boolean {
    return /^(action|parameters|reasoning|reason|app|app_name|package_name|target_app|bundle|bundle_name|task_description|template_name|title|category|summary|details|tags|importance)"\s*:/.test(text);
  }

  private static repairLeadingBrokenObjectQuote(text: string): string {
    return text.replace(/^(\{\s*)"\s*(?="[^"]+"\s*:)/, '$1');
  }
}
