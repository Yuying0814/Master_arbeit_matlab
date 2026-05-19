function text = extractTextFrom(pages)
%UNTITLED2 Summary of this function goes here
%   Detailed explanation goes here
    if isempty(pages)
        error('No pages input');
    end

    if ~isfield(pages,["markdown" "tables" "index"])
        error('Incomplete struct input');
        return
    end
    text = string({pages.markdown});
    tableHtml = {};
    tableId = {};


    for i = 1:numel(pages)
        if isempty(pages(i).tables)
            continue
        end
        tableId = [tableId {pages(i).tables.id}];
        tableHtml = [tableHtml {pages(i).tables.content}];
    end
    
    if isempty(tableHtml)
        return
    end

    tableId = string(tableId);
    pattern = strcat('[',tableId,']','(',tableId,')');
    tableContent = cellfun(@(x) extractHTMLText(htmlTree(x)),tableHtml);
    text = replace(text,pattern,tableContent);
end
