function outPages = parseDescriptionContent(pages,contents,customIds)
    defaultValue = preprocessing.page.getDescriptionFormat();
    
    for i = 1:numel(customIds)
        customId = customIds(i);
        contentIdx = find(strcmp(customId, [contents.custom_id]), 1);

        if isempty(contentIdx) || contents(contentIdx).not_finished
            pages(i).description = defaultValue;
            continue
        end

        pages(i).description = contents(contentIdx).content;
    end
    outPages = pages;
end

