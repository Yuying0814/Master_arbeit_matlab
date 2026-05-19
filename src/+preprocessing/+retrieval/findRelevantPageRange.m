function outPages = findRelevantPageRange(pages,option)
%UNTITLED3 Summary of this function goes here
%   Detailed explanation goes here
    %% 
    text = lower(preprocessing.utils.extractTextFrom(pages));
    text = regexprep(text, '(?m)^\s*(#+|-)\s*', '');
    words = arrayfun(@(s) regexp(s,'\S+','match'),text,'UniformOutput',false);
    wordCounts = cellfun(@numel,words);
    
    %%
    keywords = selectKeyword(option);
    
    %%
    titleFreqMatrix = countQueryHitsByPage(keywords.title,text);
    titleCounts = sum(titleFreqMatrix,2);
    summaryPageIdx = find(titleCounts>0)';
    
    %%
    freqMatrix = countQueryHitsByPage(keywords.feature,text);
    pageScores = computeBM25score(freqMatrix,wordCounts);

    %%
    tempRanges = selectRange(pageScores);

    if isempty(tempRanges)
        pageIdx = [];
        return
    end

    for i = 1:numel(tempRanges)
        lastPage = tempRanges{i}(end);
        if lastPage == numel(pageScores)
            continue;
        end

        if pageScores(lastPage+1)>0
            tempRanges{i} = [tempRanges{i} lastPage+1];
        end
    end

    %% Merge overlapping or adjacent page ranges.
    allPageNum = unique([tempRanges{:}]);
    breakIdx = find(diff(allPageNum) > 1);
    startIdx = [1, breakIdx + 1];
    endIdx = [breakIdx, numel(allPageNum)];

    pageRanges = arrayfun(@(x, y) allPageNum(x:y), startIdx, endIdx, ...
        'UniformOutput', false);
    pageIdx = [pageRanges{:}];

    %% Output
    for i = 1:numel(pages)
        pages(i).result_retrieval.BM25score = pageScores(i);
        pages(i).result_retrieval.counts_reg_sum_keyword = titleCounts(i);
        if ismember(i,pageIdx)
            pages(i).result_retrieval.is_reg_map_relevant = true;
        else
            pages(i).result_retrieval.is_reg_map_relevant = false;
        end

        if ismember(i,summaryPageIdx)
            pages(i).result_retrieval.is_reg_sum_relevant = true;
        else
            pages(i).result_retrieval.is_reg_sum_relevant = false;
        end
    end

    outPages = pages;
end

function freqMatrix = countQueryHitsByPage(query,allTexts)
    freqCell = arrayfun(@(x) countQueryHits(query,x),allTexts,'UniformOutput',false);
    freqMatrix = vertcat(freqCell{:});
end

function freq = countQueryHits(query,oneText)
    query = query(:).';
    matchPositions = regexp(oneText,query);
    %matchWord = regexp(oneText,query,'match');  %------debug-------
    %appendDebugData(matchWord,'matchWord');     %------debug-------
    freq = cellfun(@numel,matchPositions);
    freq = freq(:).';
end

function idf = computeInvDocFreq(freqMatrix)
    nPages = size(freqMatrix, 1);
    freqMask = freqMatrix>0;
    docFreq = sum(freqMask,1);
    idf = log(1+(nPages-docFreq+0.5)./(docFreq+0.5));
end

function pageScores = computeBM25score(freqMatrix,wordCounts)
    idf = computeInvDocFreq(freqMatrix);
    idf = idf(:)';
    docLength = wordCounts(:);
    avgDocLength = mean(wordCounts);
    k1 = 1.5;
    b = 0.75;
    
    if avgDocLength == 0
        avgDocLength = 1;
    end
    
    lengthNorm = 1 - b + b*docLength/avgDocLength;
    scoreMatrix = (k1 + 1)*idf.*freqMatrix./(freqMatrix + k1.*lengthNorm);
    pageScores = sum(scoreMatrix,2);
    pageScores = pageScores';
end

function keywords = selectKeyword(option)
%select keywords depend on option
    keywords = struct();
    option = string(lower(option));

    switch(option)
        case "register"
            keywords.title = { ...
                ['reg\.?(?:isters?)\s+' ...
                '(?:maps?|mappings?|descriptions?|tables?|lists?|definitions?|overviews?|summar(?:y|ies)|references?)'], ...
                
                ['address(?:es)?\s+' ...
                '(?:maps?|mappings?|descriptions?|tables?|lists?|definitions?|overviews?|summar(?:y|ies)|references?)'],  ...
                
                'memory\s+map' ...
                };
            keywords.feature = {...
                '\<addr\.?\>',...
                '\<address\>', ...
                '\<bank\>', ...
                '(?<!-)\<bits?(?:\s+|-\s*)(?:fields?|descriptions?)\>', ...
                '\<bits?\s*\d+(?:\s*-\s*\d+|\s*:\s*\d+)?\>', ...
                '\<bits?\>(?!\s*[-]?\s*(?:fields?|descriptions?))(?!\s*\d)', ...
                '(?<!\<bit )(?<!\<bits )(?<!\<bit-)(?<!\<bits-)(?<!\<bit- )(?<!\<bits- )\<fields?\>', ...
                '\<reg\.?\>', ...
                '\<registers?\>', ...
                '\<registers?\s*names?\>', ...
                '\<registers?\s*pointers?\>', ...
                '\<registers?\s*addr(?:\.|ess(?:es)?)\>', ...
                '\<hex\>', ...
                '\<decimal\>', ...
                '\<dec\.?\>', ...
                'initial value', ...
                'default value',...
                'reset value',...
                '\<(?:r\s*/\s*w|w\s*/\s*r|r\s*/\s*o|w\s*/\s*o|r\s*w|w\s*r|r\s*o|w\s*o|r|w)\>', ...
                'read\s*/\s*write', ...
                'write\s*/\s*read', ...
                'read only', ...
                'write only', ...
                'readable', ...
                'writable', ...
                '(?<!all rights )\<reserved\>', ...
                '0x[0-9a-f]{2}', ...
                '\<[0-9a-fA-F]{2}h\>', ...
                '\<(?:[01]{4}\s?)+\>'
                };
    end
end

function pageRanges = selectRange(pageScores)
% Extract page ranges while allowing gaps of up to m consecutive low-score pages.
    
    if isempty(pageScores) || max(pageScores) <= 0
        pageRanges = {};
        return
    end

    m = 2; % Maximum number of consecutive zero-valued pages allowed.
    n = 2; % Mimimum number of consecutive nonzero-valued pages allowed.
    negativeMask = (pageScores < 0.2*max(pageScores));
    d = diff([0 negativeMask 0]);
    zStartIdx = find(d == 1);             
    zEndIdx = find(d == -1) - 1;   
    
    invalid = (zEndIdx - zStartIdx + 1) > m;
    invalidStart = zStartIdx(invalid);
    invalidEnd = zEndIdx(invalid);
    startIdx = 1;
    pageRanges = {};
    
    for i = 1:numel(invalidStart)
        endIdx = invalidStart(i) - 1;
        
        if endIdx-startIdx +1 > n && startIdx <= endIdx
            pageRanges{end+1} = [startIdx endIdx];
        end
        
        startIdx = invalidEnd(i)+1;
    end
    
    if numel(pageScores)-startIdx + 1 > n
        pageRanges{end+1} = [startIdx numel(pageScores)];
    end
    
    for i = 1:numel(pageRanges)
        pageRanges{i} = pageRanges{i}(1):pageRanges{i}(2);
    end
end