function isDetected = detectTocEntry(thisLine)
% Detect whether a line is TOC-like.

    thisLine = lower(strtrim(thisLine));

    exclusions = [
        '^(?!\d+(?:\.\d+)*$)' ...                        % exclude pure number line, e.g. 1.1 or 2.3.4
        '(?!.*\d+\s*[/|]\s*\d+$)' ...                    % exclude page footing ending with 2 / 21 or 2 | 21
        '(?!.*\d+\s+of\s+\d+$)' ...                % exclude page footing ending with 2 of 21
        '(?!#*\s*.+\s+\d+\s*(?:[/|]\s*\d+|of\s+\d+)$)' ... % exclude heading-like line ending with 4 / 42 or 4 of 42
        '(?!.*(?:19|20)\d{2}\s*$)' ...                   % exclude lines ending with year 19xx or 20xx
        '(?!.*(?:pages?|figures?|tables?)\s*\d+$)' ...   % exclude lines ending with page/figure/table xx
        '(?!.*(?:pages?|figures?|tables?)\s*\d+\s+of\s+\d+\s*$)' ... % exclude lines ending with page/figure/table xx of yy
        '(?!.*=\s*\d+\s*$)' ...                          % exclude simple equations ending with = number
        '(?!.*\d{3}\s+\d{3}\s+\d{3}\s*$)' ...            % exclude telephone-like numbers ending with xxx xxx xxx
        '(?!.*(?<!\w)(?:add(ed)?|change[ds]?|deleted?)(?!\w))' ...       % exclude revision-history lines containing added or changed
        '(?!.*(?<!\w)(?:figures?\s+\d+|tables?\s+\d+)(?!\w))' ...       % exclude lines containing figure or table
        '(?!#*\s*(?:table|figure)\s+\d+\b)' ...          % exclude line starting with table/figure number
        '(?!\s*-\s*(?:table|figure)\s+\d+\b)' ...        % exclude bullet line starting with table/figure number
        '(?!.*,(?:\s*|\.{2,}\s*)\d+$)'
    ];

    pattern1 = [
        exclusions ...
        '^#*\s*\d+(?:\.\d+)*\.?\s+.+?(?:\s|\.{2,}\s*)\d+$' ...
    ]; % match numbered TOC entry, e.g. 4.1 register map ... 7

    pattern2 = [
        exclusions ...
        '(?!#*\s*(?:table|figure)\s+\d+\.?\s+.*(?:\s|\.{2,}\s*)\d+$)' ...
        '^#*\s*(?!\d+(?:\.\d+)*\.?\s+)[^\s].*?(?:\s|\.{2,}\s*)\d+$' ...
    ]; % match non-numbered TOC entry, e.g. Introduction ... 3

    pattern3 = [
        exclusions ...
        '^\s*-\s+[^\d].*?(?:\s+|\.{2,}\s*)\d+\s*$' ...
    ]; % match bullet-style TOC entry, e.g. - Introduction 3

        
    matchPattern1 = preprocessing.utils.matchPattern(thisLine, pattern1);
    matchPattern2 = preprocessing.utils.matchPattern(thisLine, pattern2);
    matchPattern3 = preprocessing.utils.matchPattern(thisLine, pattern3);

    isDetected = matchPattern1 || matchPattern2 || matchPattern3;
end