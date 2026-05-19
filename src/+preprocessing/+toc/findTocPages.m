function outPages = findTocPages(pages)
% Detect TOC-like pages and return their page indices.classification
%
% Input:
%   pages (struct): Page array extracted from ocrResult.pages.
%
% Output:
%   tocIdx (double): Indices of pages classified as TOC-like.
%   outPages (struct): Updated page array with per-page TOC scores and
%       repaired markdown content when OCR line reconstruction succeeds.

    import preprocessing.utils.matchPattern

    if isempty(pages)
        error('No pages input');
    end

    %% Initialisation
    titlePage = -999;
    hasTitle = false;
    tocIdx = [];
    fixedBuffer = cell(1,numel(pages));
    scoresArray = zeros(1,numel(pages));
    
    %% Define the TOC search range as the first 20% and the last 20% of pages.
    nPages = numel(pages);
    first20PercentPages = 1:ceil(0.2*nPages);
    last20PercentPages = ceil(0.8*nPages):nPages;
    searchRange = unique([first20PercentPages last20PercentPages], 'stable');
    
    for i = searchRange
        %% Split the page markdown into lines for analysis
        text = preprocessing.utils.extractTextFrom(pages(i));
        lines = preprocessing.utils.text2lines(text);
        nLines = numel(lines);

        %% Detect a TOC title on the current page, e.g., "Contents", and record its line index and page number.   
        isTitlePage = false;
        tocTitleLineIndex = 0;

        if ~hasTitle
            lowerLines = cellfun(@lower, lines, 'UniformOutput', false); %
            isDetected = cellfun(@preprocessing.toc.detectTocTitle, lowerLines);

            if any(isDetected)
                hasTitle = true;
                isTitlePage = true;
                tocTitleLineIndex = find(isDetected, 1, 'first');
                titlePage = i;
            end
        end

        %% Count TOC-like lines, e.g., section number + title + dot leaders + page number
        usedLines = lines;
        counts = countTocLikeLines(usedLines);
        
        %% Pre-fix the protentially fragmented OCR output, and then count TOC-like lines
        usedFixedLines = {};
        preFixedLines = preFixTocLines(usedLines,tocTitleLineIndex);
        preFixedCounts = countTocLikeLines(preFixedLines);
        

        if counts < preFixedCounts  % select a better result
            usedFixedLines = preFixedLines;
            usedLines = preFixedLines;
            counts = preFixedCounts;
            %disp('preFixed'); %---------------------debug------------------------------
            %disp(i);
        end

        %% Compute the final TOC-like score
        scores = 0;
        nLines = numel(usedLines);

        if isTitlePage
            scores = scores + 1;
        end

        if nLines>0
            scores = scores + counts/nLines;
        end

        scoresArray(i) = scores;

        
        %% Save the result of fix-functions only when the result of fix-functions is adopted and improves TOC-pattern detection.
        if ~isempty(usedFixedLines)
            fixedContent = cellfun(@(x) [x newline],usedFixedLines,'UniformOutput',false);
            fixedBuffer{i} = [fixedContent{:}];             
        end
    end
    
    %% Filter the TOC page range based on scoresArray  
    threshold = 0.2;
    tocIdx = findBestSegment(scoresArray,threshold);
       
    if ~isempty(tocIdx)

        if hasTitle
            tocIdx = tocIdx(tocIdx>=titlePage); % pageRange must start from the TOC title page.
        end
        
        nextPage = tocIdx(end) + 1;
        if nextPage <= nPages && scoresArray(nextPage) > 0 
            tocIdx = [tocIdx nextPage]; % Include one subsequent page with a score greater than 0.   
        end
    end

    %% 
    isNonEmpty = ~cellfun(@isempty, fixedBuffer(tocIdx));
    validIdx = tocIdx(isNonEmpty);

    if ~isempty(validIdx)
        [pages(validIdx).markdown] = fixedBuffer{validIdx};
    end

    %% Output
    for i = 1:numel(pages)
        if ismember(i, tocIdx)
            pages(i).result_toc.is_toc = true;
        else
            pages(i).result_toc.is_toc = false;
        end
        pages(i).result_toc.score = scoresArray(i);
    end
    outPages = pages;
end

function tocIdx = findBestSegment(scoresArray,threshold)
%maximum scoring contiguous subsequence
    scoresArray = scoresArray - threshold;
    currentStart = 1;
    bestStart = 1;
    bestEnd = 1;
    currentSum = scoresArray(1);
    bestSum = scoresArray(1);
    
    for i=2:numel(scoresArray)
        if currentSum < 0
            currentSum = scoresArray(i);
            currentStart = i;
        else
            currentSum = currentSum + scoresArray(i);
        end

        if currentSum > bestSum
            bestSum = currentSum;
            bestStart = currentStart;
            bestEnd = i;
        end
    end

    if bestSum >= 0
        tocIdx = bestStart:bestEnd;
    else 
        tocIdx = [];
    end
end

function tocLikeCounts = countTocLikeLines(lines)
% Count TOC-like lines while enforcing nondecreasing ending page numbers.

    tocLikeCounts = 0;
    pageNums = [];
    for i = 1:numel(lines)
        thisLine = lines{i};
        if ~preprocessing.toc.detectTocEntry(thisLine)
            continue;
        end
        %disp(thisLine); %-----------------------debug-------------------
        token = regexp(thisLine, '(\d+)\s*$', 'tokens', 'once');
        pageNums = [pageNums str2double(token{1})];
    end
    
    if numel(pageNums) <= 1
        tocLikeCounts = numel(pageNums);
        return
    end
    
    monotonicMask = diff(pageNums) >= 0;
    monotonic = sum(monotonicMask)/numel(monotonicMask);
    tocLikeCounts = round(numel(pageNums)*monotonic);
end

function fixedLines = preFixTocLines(lines,matchedLine)
    for i = matchedLine+1:numel(lines)-1
        thisLine = lines{i};
        if isempty(thisLine)
            continue
        end
        nextLine = lines{i+1};
        if ~preprocessing.toc.detectTocEntry(thisLine) && ~preprocessing.toc.detectTocEntry(nextLine)
            newLine = [thisLine ' ... ' nextLine];
            if preprocessing.toc.detectTocEntry(newLine)
                lines{i} = newLine;
                lines{i+1} = '';
                %disp(newLine); % -----------------------debug----------------
            end
        end
    end
    fixedLines = lines(~cellfun('isempty',lines));
end