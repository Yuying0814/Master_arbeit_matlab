function  outPages = removeHeaderFooter(pages)
%UNTITLED3 Summary of this function goes here
%   Detailed explanation goes here
    % Identify header and footer like lines
    

    if isempty(pages)
        error('No pages input');
    end
    
    repeatedLines = findRepeatedLines(pages);
    outPages = pages;

    for i = 1:numel(pages)
        %% Split the page markdown into lines for pattern analysis
        text = pages(i).markdown;
        lines = preprocessing.utils.text2lines(text);
        trimmedLines = strtrim(lines);

        %% Remove repeated lines
        repeatedMask = ismember(trimmedLines,repeatedLines);
        lines = lines(~repeatedMask);

        %% Find footer lines e.g. page 4/21
        footerMask = cellfun(@isFooter,lines);
        lines = lines(~footerMask);

        %% Rebuild text
        lines = cellfun(@(x) [x newline], lines,'UniformOutput',false);
        newText = [lines{:}];
        
        outPages(i).markdown = newText;
    end
end

function  repeatedLines = findRepeatedLines(pages)
    searchRange = 1:ceil(0.5*numel(pages));
    allLines = {};
    for i = searchRange
    % Split the page markdown into lines for pattern analysis
        text = pages(i).markdown;
        lines = preprocessing.utils.text2lines(text);
        lines = strtrim(lines);
        lines = unique(lines);
        allLines = [allLines lines];
    end
    [uniqueLines, ~, idx] = unique(allLines);
    counts = accumarray(idx,1);
    repeatedLines = uniqueLines(counts>ceil(0.3*numel(pages)));
    %disp(repeatedLines);   %-----------------------------------debug-----
end

function isFooter = isFooter(thisLine)
    thisLine = lower(thisLine);
    thisLine = strtrim(thisLine);

    pattern = '^(?:(?:pages?|pg\.?|p\.?)\s*:?\s*)?(\d+)\s*(?:/|\||of)\s*(\d+)$';
    tokens = regexp(thisLine, pattern, 'tokens', 'once');
    if isempty(tokens)
        isFooter = false;
        return;
    end

    currentPage = str2double(tokens{1});
    totalPages = str2double(tokens{2});

    isFooter = currentPage >= 1 && totalPages >= 1 && currentPage <= totalPages;
    %disp(thisLine);        %-----------------------------------debug-----
end