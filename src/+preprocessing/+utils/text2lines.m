function lines = text2lines(text)
%UNTITLED Summary of this function goes here
%   Detailed explanation goes here
    text = regexprep(text, '\r\n?', '\n');
    allLines = regexp(text, '\n', 'split');
    % eliminate empty lines
    blankMask = cellfun(@isempty, strtrim(allLines));
    lines = allLines(~blankMask);
end