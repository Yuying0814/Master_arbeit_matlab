function responseFormat = buildJSONSchema(value,schemaName)
    arguments
        value (1,1) struct
        schemaName (1,1) string = "output_schema"
    end
    
    schema = buildSchema(value);

    responseFormat = struct( ...
        "type","json_schema", ...
        "json_schema",struct( ...
            "name",schemaName, ...
            "schema",schema) ...
            ); 
end

function schema = buildSchema(value)
    if isequal(value, {}) || isequal(value, []) || isequal(value, struct()) || ...
       (isstruct(value) && isempty(value)) || (islogical(value) && isempty(value))
        error("OpenaiBatch:InvalidEmpty", ...
            "Empty examples {}, [], struct(), struct.empty, and logical.empty are not allowed.");
    end

    if iscell(value)||(~isscalar(value) && ~ischar(value))
        schema = arraySchema(value);
        return;
    end

    if isstruct(value)
        schema = objectSchema(value);
        return;
    end

    if ischar(value) || isstring(value)
        schema = struct("type", "string");
        return;
    end

    if islogical(value)
        schema = struct("type", "boolean");
        return;
    end

    if isnumeric(value)
        if isscalar(value) && isfinite(value) && value == fix(value)
            schema = struct("type", "integer");
        else
            schema = struct("type", "number");
        end
        return;
    end
    
    error("OpenaiBatch:UnsupportedType", ...
        "Unsupported JSONL type: %s.", class(value));
end

function schema = objectSchema(value)  
    fieldNames = fieldnames(value);
    properties = struct();
    
    for i = 1:numel(fieldNames)
        fieldName = fieldNames{i};
        properties.(fieldName) = buildSchema(value.(fieldName));
    end

    schema = struct( ...
        "type","object", ...
        "properties",properties, ...
        "required",string(fieldNames(:))', ...
        "additionalProperties",false);
end

function schema = arraySchema(value)
    if isempty(value)
        schema = struct( ...
            "type", "array", ...
            "items", struct("type", "string") ...
        );
        return;
    end

    if iscell(value)
        itemSchemas = cell(1, numel(value));
        for i = 1:numel(value)
            itemSchemas{i} = buildSchema(value{i});
        end

        if allSame(itemSchemas)
            itemsSchema = itemSchemas{1};
        else
            itemsSchema = struct("anyOf", {itemSchemas});
        end
    elseif isnumeric(value)
        if ~all(isfinite(value), "all")
            error("OpenaiBatch:InvalidNumericValue", ...
                "Numeric examples must not contain NaN or Inf.");
        end
        
        if all(value == fix(value), "all")
            itemsSchema = struct("type", "integer");
        else
            itemsSchema = struct("type", "number");
        end
    else
        itemsSchema = buildSchema(value(1));
    end

    schema = struct( ...
        "type", "array", ...
        "items", itemsSchema ...
    );
end

function tf = allSame(itemSchemas)
    tf = true;
    for i = 2:numel(itemSchemas)
        if ~strcmp(jsonencode(itemSchemas{1}), jsonencode(itemSchemas{i}))
            tf = false;
            return;
        end
    end
end

