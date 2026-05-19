function [regPageIdx,regSumIdx]= resolveTocEntries(tocEntries)
%RESOLVETOCENTRIES Resolve register-related page ranges from TOC entries.
%
% Input:
%   tocEntries (struct): TOC entry array with content, continuation_lines,
%       page_number, section_level, and source_index fields.
%
% Output:
%   pageRange (cell): Merged page ranges that are likely to contain
%       register maps or register descriptions.
    
    if isempty(tocEntries)
        regPageIdx = [];
        regSumIdx = [];
        return
    end

    %% Define patterns related to register maps and register descriptions.
    normalPatterns = { ...
        '\<registers?\s+maps?\>', ...
        '\<registers?\s+descriptions?\>', ...
        '\<registers?\s+definitions?\>', ...
        '\<registers?\s+summar(?:y|ies)\>', ...
        '\<registers?\s+lists?\>', ...
        '\<registers?\s+tables?\>', ...
        '\<registers?\s+addresses?\>', ...
        '\<address\s+maps?\>', ...
        '\<memory\s+maps?\>', ...
        '\<bits?\s+fields?\>', ...
        '\<fields?\s+descriptions?\>', ...
        '\<registers?\s+overview\>', ...
        '\<registers?\s+reference\>', ...
        '\<registers?\>', ...
        '\<reg\>', ...
        '\<reg\.' ...
    };
    
    summaryPatterns = {...
        '\<registers?\s+maps?\>', ...
        '\<registers?\s+descriptions?\>', ...
        '\<registers?\s+definitions?\>', ...
        '\<registers?\s+summar(?:y|ies)\>', ...
        '\<registers?\s+lists?\>', ...
        '\<registers?\s+tables?\>', ...
        '\<memory\s+maps?\>', ...
        };

    regPageIdx = findPageRange(tocEntries,normalPatterns);
    regSumIdx = findExactPages(tocEntries,summaryPatterns);
end

function pageIdx = findPageRange(tocEntries,patterns)
    %% Initialization
    currentIdx = 1;
    keepLine = false(1, numel(tocEntries));

    %% Combine main content and continuation lines for keyword matching.
    content = {tocEntries.content};
    continuationLines = {tocEntries.continuation_lines};
    contents = strcat(content, {newline}, continuationLines);
    contents = lower(contents);

    %% Mark register-related TOC entries and their subordinate entries.
    while currentIdx <= numel(tocEntries)
        thisContent = contents{currentIdx};
        thisLevel = tocEntries(currentIdx).section_level;
        matched = any(cellfun(@(p) preprocessing.utils.matchPattern(thisContent, p), patterns));

        if matched
            keepLine(currentIdx) = true;

            % Level-0 entries are kept only when directly matched.
            if thisLevel == 0
                currentIdx = currentIdx + 1;
                continue
            end

            if currentIdx == numel(tocEntries)
                break
            end

            % Use the matched entry as an anchor and keep its subsections.
            anchorLevel = tocEntries(currentIdx).section_level;
            currentIdx = currentIdx + 1;

            while currentIdx <= numel(tocEntries)
                currentLevel = tocEntries(currentIdx).section_level;

                % Level-0 entries inside an anchored range are retained.
                if currentLevel == 0
                    keepLine(currentIdx) = true;
                    currentIdx = currentIdx + 1;
                    continue
                end

                % Stop when a same-level or higher-level section is reached.
                if currentLevel <= anchorLevel
                    break
                end

                keepLine(currentIdx) = true;
                currentIdx = currentIdx + 1;
            end
        else
            currentIdx = currentIdx + 1;
        end
    end

    %% Return an empty result when no register-related entry is found.
    if ~any(keepLine)
        pageIdx = [];
        pageRange = {};
        return
    end

    %% Convert marked TOC lines into continuous TOC-entry segments.
    mask = diff([0 keepLine 0]);
    startIdx = find(mask == 1);
    endIdx = find(mask == -1) - 1;

    %% Resolve segment start pages from the first selected TOC entries.
    startPage = {tocEntries(startIdx).page_number};
    startPage = str2double(startPage);

    %% Resolve segment end pages from the next TOC entry or document end.
    endPage = zeros(size(endIdx));

    for i = 1:numel(endIdx)
        if endIdx(i) < numel(tocEntries)
            endPage(i) = str2double(tocEntries(endIdx(i) + 1).page_number);
        else
            endPage(i) = str2double(tocEntries(endIdx(i)).page_number);
        end
    end

    %% Correct abnormal ranges caused by non-monotonic TOC page numbers.
    badRange = endPage < startPage;

    if any(badRange)
        warning('Some page ranges had endPage < startPage');
    end

    endPage = max(endPage, startPage);

    %% Expand each page interval into an explicit page-number array.
    tempRange = arrayfun(@(x, y) x:y, startPage, endPage, ...
        'UniformOutput', false);

    %% Merge overlapping or adjacent page ranges.
    allPageNum = unique([tempRange{:}]);
    breakIdx = find(diff(allPageNum) > 1);
    startIdx = [1, breakIdx + 1];
    endIdx = [breakIdx, numel(allPageNum)];

    pageRange = arrayfun(@(x, y) allPageNum(x:y), startIdx, endIdx, ...
        'UniformOutput', false);
    pageIdx = [pageRange{:}];
end

function pageIdx = findExactPages(tocEntries,patterns)
    %% Initialization
    keepLine = false(1, numel(tocEntries));

    %% Combine main content and continuation lines for keyword matching.
    content = {tocEntries.content};
    continuationLines = {tocEntries.continuation_lines};
    contents = strcat(content, {newline}, continuationLines);
    contents = lower(contents);

    %% Mark register-related TOC entries and their subordinate entries.
    for i = 1:numel(tocEntries)
        thisContent = contents{i};
        matched = any(cellfun(@(p) preprocessing.utils.matchPattern(thisContent, p), patterns));

        if matched
            keepLine(i) = true;
        end
    end

    %% Return an empty result when no register-related entry is found.
    if ~any(keepLine)
        pageIdx = [];
        return
    end

    %% Convert marked TOC lines into continuous TOC-entry segments.
    mask = diff([0 keepLine 0]);
    startIdx = find(mask == 1);
    endIdx = find(mask == -1) - 1;
    
    %% Resolve segment start pages from the first selected TOC entries.
    startPage = {tocEntries(startIdx).page_number};
    startPage = str2double(startPage);

    %% Resolve segment end pages from the next TOC entry or document end.
    endPage = zeros(size(endIdx));

    for i = 1:numel(endIdx)
        if endIdx(i) < numel(tocEntries)
            endPage(i) = str2double(tocEntries(endIdx(i) + 1).page_number);
        else
            endPage(i) = str2double(tocEntries(endIdx(i)).page_number);
        end
    end
    
    %% Correct abnormal ranges caused by non-monotonic TOC page numbers.
    badRange = endPage < startPage;

    if any(badRange)
        warning('Some page ranges had endPage < startPage');
    end

    endPage = max(endPage, startPage);

    %% Expand each page interval into an explicit page-number array.
    tempRange = arrayfun(@(x, y) x:y, startPage, endPage, ...
        'UniformOutput', false);

    %% Merge overlapping or adjacent page ranges.
    allPageNum = unique([tempRange{:}]);
    breakIdx = find(diff(allPageNum) > 1);
    startIdx = [1, breakIdx + 1];
    endIdx = [breakIdx, numel(allPageNum)];

    pageRange = arrayfun(@(x, y) allPageNum(x:y), startIdx, endIdx, ...
        'UniformOutput', false);
    pageIdx = [pageRange{:}];
end