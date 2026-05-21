function outPages = parseClassificationContent(pages,contents,customIds)
    defaultValue = preprocessing.page.getClassificationFormat();
    
    for i = 1:numel(customIds)
        customId = customIds(i);
        contentIdx = find(strcmp(customId, [contents.custom_id]), 1);

        if isempty(contentIdx) || contents(contentIdx).not_finished
            pages(i).classification = defaultValue;
            continue
        end

        pages(i).classification = contents(contentIdx).content;
    end

    outPages = pages;
end

