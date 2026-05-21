function tocEntries = extractTocEntry(tocPages)
%UNTITLED5 Summary of this function goes here
%   Detailed explanation goes here
    if isempty(tocPages)
        tocEntries = struct([]);
        return
    end
    
    allLines = {};
    tocEntries = struct('section_level',{},'section',{},'content',{},'page_number',{},'continuation_lines',{},'source_index',{});
    sourceIdx = [];
    preSectionNum = 0;
    sectionStart = false;
    
    for i=1:numel(tocPages)
        text = preprocessing.utils.extractTextFrom(tocPages(i));
        pageIdx = tocPages(i).index;
        
        lines = preprocessing.utils.text2lines(text);
        nLines = numel(lines);
        
        sourceIdx = [sourceIdx,repmat(pageIdx, 1,nLines)];
        allLines = [allLines,lines];
    end
    
    tocMask = cellfun(@preprocessing.toc.detectTocEntry,allLines);
    
    idx = 1;
    continuationLines = '';

    for i = 1:numel(allLines)
        thisLine = allLines{i};
        if tocMask(i)
            
            pageToken = regexp(thisLine, '(\d+)\s*$', 'tokens','once');
            contentToken = regexp(thisLine, '(.*?)\s*\.*\s*\d+\s*$', 'tokens','once');
            
            [sectionNum,sectionLevel] = sectionIdent(thisLine); 

            if strcmp(sectionNum,'1') && ~sectionStart
                sectionStart = true;
            end

            if sectionStart && sectionLevel == 1   
                if isValidSectionNumber(sectionNum,preSectionNum)
                    if ~isempty(sectionNum)
                        preSectionNum = str2double(sectionNum);
                    end
                else
                    sectionNum = '';
                    sectionLevel = 0;
                end
            end
                    
            pageNum = pageToken{1};
            
            content = contentToken{1};
            content = regexprep(content, '^\s*(?:#+|-*)\s*', '');
            
            if ~isempty(sectionNum)
                content = regexprep(content, ['^\s*' regexptranslate('escape', sectionNum) '\.?\s*'], '', 'once');
            end
            content = strtrim(content);

            if ~isempty(continuationLines) && idx > 1
                tocEntries(idx-1).continuation_lines = continuationLines;
                continuationLines = '';
            end
            
            tocEntries(idx).section = sectionNum;
            tocEntries(idx).section_level = sectionLevel;
            tocEntries(idx).page_number = pageNum;
            tocEntries(idx).content = content;
            tocEntries(idx).continuation_lines = '';
            tocEntries(idx).source_index = sourceIdx(i);
            
            idx = idx + 1;
            

        elseif idx>1
            continuationLines = [continuationLines thisLine newline];
        end
    end

     if ~isempty(continuationLines) && idx > 1
         tocEntries(idx-1).continuation_lines = continuationLines;
     end
end

function [sectionNum,sectionLevel] = sectionIdent(thisLine)
    sectionNum = '';
    
    %% Remove common Markdown markers before section detection.
    thisLine = strtrim(thisLine);
    cleanLine = regexprep(thisLine, '^\s*#+\s*', '');
    cleanLine = regexprep(cleanLine, '^\s*[-*]\s*', '');
    
    %% Match section-like numbers:
    sectionNumToken = regexp(cleanLine,'^(\d+(?:\.\d+)*)\.?\s+','tokens','once');
    
    if isempty(sectionNumToken)
        if preprocessing.utils.matchPattern(thisLine,'^#')
            sectionLevel = 1;
            return
        end
        sectionLevel = 0;
        return
    end
    
    sectionNum = sectionNumToken{1};
    sectionLevel = count(string(sectionNum), ".") + 1;
    
    %% First simple validation of the section number: First number must not greater than 30
    firstNumToken = regexp(sectionNum, '^\d+', 'match', 'once');
    firstNum = str2double(firstNumToken);

    if firstNum > 30
        sectionNum = '';
        sectionLevel = 0;
        return
    end 
end

function tf = isValidSectionNumber(sectionNum,preSectionNum)
    %% Strict validation of the section number
    if isempty(sectionNum)
        tf = true;
        return
    end
    firstNum = str2double(sectionNum);
    tf = (firstNum == preSectionNum +1);
end